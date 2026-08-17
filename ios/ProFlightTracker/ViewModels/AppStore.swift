import Foundation
import Observation

/// Central observable store: watchlist, snapshots, alerts, refresh pipeline.
/// Persists lightweight state in UserDefaults so the app renders instantly.
@Observable
final class AppStore {
    private enum Keys {
        static let flights = "pft.flights.v1"
        static let snapshots = "pft.snapshots.v1"
        static let alerts = "pft.alerts.v1"
        static let pushToken = "pft.pushToken.v1"
    }

    var flights: [TrackedFlight] = []
    var snapshots: [String: FlightSnapshot] = [:]
    var alerts: [FlightAlert] = []
    var refreshing: Set<String> = []
    /// Flight ids with a brief request in flight (strictly user-initiated).
    var briefing: Set<String> = []
    /// Flight ids whose AI narrative is still being written.
    var narrativePending: Set<String> = []

    /// Placeholder token registered with the engine's tracking service.
    /// Replaced by a real APNs/Expo token when the app ships to devices.
    let pushToken: String

    private let defaults = UserDefaults.standard

    init() {
        if let token = defaults.string(forKey: Keys.pushToken) {
            pushToken = token
        } else {
            let token = "rork-ios-preview-\(UUID().uuidString.lowercased())"
            defaults.set(token, forKey: Keys.pushToken)
            pushToken = token
        }
        flights = load([TrackedFlight].self, key: Keys.flights) ?? []
        snapshots = load([String: FlightSnapshot].self, key: Keys.snapshots) ?? [:]
        alerts = load([FlightAlert].self, key: Keys.alerts) ?? []
    }

    // MARK: - Derived

    var sortedFlights: [TrackedFlight] {
        flights.sorted { lhs, rhs in
            let lhsDate = TimeFmt.parseISO(snapshots[lhs.id]?.flight?.scheduledOut) ?? .distantFuture
            let rhsDate = TimeFmt.parseISO(snapshots[rhs.id]?.flight?.scheduledOut) ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// Tab badge counts only unread DETERIORATIONS — "eased/improved" news
    /// sits in the drawer without demanding attention.
    var unreadAlertCount: Int { alerts.filter { !$0.isRead && !$0.isImprovement }.count }

    func alerts(for flightKey: String) -> [FlightAlert] {
        alerts.filter { $0.flightKey == flightKey }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Watchlist management

    /// Validates the flight against the engine, adds it to the watchlist,
    /// registers server-side tracking, and runs the first check.
    func addFlight(ident: String, date: Date, intervalMinutes: Int) async throws {
        let cleaned = ident.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.count >= 3 else {
            throw APIError.server("Enter a flight number like DL244.")
        }
        let dateString = TimeFmt.apiDate(date)
        let key = "\(cleaned)_\(dateString)"
        guard !flights.contains(where: { $0.id == key }) else {
            throw APIError.server("You're already tracking \(cleaned) on \(dateString).")
        }

        let status = try await API.flightStatus(flight: cleaned, date: dateString)
        guard let found = status.data?.flights?.first else {
            let reason = status.errors?.first?.error ?? "No flights found for \(cleaned) on that date."
            throw APIError.server(reason)
        }

        // First moment notifications matter — ask now, not at app launch.
        // No-op once the user has answered.
        NotificationService.requestAuthorizationIfNeeded()

        let tracked = TrackedFlight(ident: cleaned, date: dateString, intervalMinutes: intervalMinutes)
        flights.append(tracked)
        var snapshot = FlightSnapshot()
        snapshot.flight = pickBestLeg(status.data?.flights) ?? found
        snapshots[tracked.id] = snapshot
        persist()

        // Register with the engine's tracker (best effort — server pushes on risk change).
        let token = pushToken
        Task.detached {
            try? await API.startTracking(flight: cleaned, date: dateString,
                                         intervalMinutes: intervalMinutes, pushToken: token)
        }

        await refresh(tracked, statusEnvelope: status)
    }

    func remove(_ flight: TrackedFlight) {
        flights.removeAll { $0.id == flight.id }
        snapshots[flight.id] = nil
        persist()
        Task.detached {
            try? await API.stopTracking(flight: flight.ident, date: flight.date)
        }
    }

    // MARK: - Refresh pipeline

    func refreshAll() async {
        // Sequential on purpose: AeroAPI allows ~10 result sets/minute.
        // Final flights (server signalled refresh_after_seconds: null) are
        // done — refreshing them buys nothing with paid queries.
        for flight in flights where snapshots[flight.id]?.isFinal != true {
            await refresh(flight)
        }
    }

    func refresh(_ flight: TrackedFlight, statusEnvelope prefetched: FlightStatusEnvelope? = nil) async {
        guard !refreshing.contains(flight.id) else { return }
        refreshing.insert(flight.id)
        defer { refreshing.remove(flight.id) }

        var snapshot = snapshots[flight.id] ?? FlightSnapshot()
        snapshot.refreshError = nil
        var sourcePullTime: Date?

        do {
            // Phase 1 — the flight itself, so we know the horizon.
            if let prefetched {
                // Add-flow: the validation call already paid for a full
                // status pull — reuse it rather than buying another query.
                snapshot.flight = pickBestLeg(prefetched.data?.flights) ?? snapshot.flight
                sourcePullTime = TimeFmt.parseISO(prefetched.pullTime)
            } else {
                do {
                    // Main refresh: /api/flight/live — ONE paid query instead
                    // of two, returning the server-computed phase, predicted
                    // times, taxi assessment, and status-only verdict.
                    // edct=cached keeps FAA-controlled times alive between
                    // brief runs.
                    let envelope = try await API.flightLive(flight: flight.ident, date: flight.date)
                    let live = StoredLive(envelope: envelope)
                    snapshot.live = live
                    sourcePullTime = live.fetchedAt
                    // Fold the live layer's fresher times back into the
                    // last-known leg so the header and the derived-phase
                    // guard never lag it.
                    if let leg = snapshot.flight {
                        snapshot.flight = FlightPhaseDerivation.patchedLeg(leg, with: envelope)
                    }
                } catch {
                    // Fallback: the original status path still answers when
                    // /live is unavailable — no live layer, but the derived
                    // phase guard keeps every phase display honest.
                    print("[Store] /flight/live failed for \(flight.id), falling back to /flight/status: \(error)")
                    let status = try await API.flightStatus(flight: flight.ident, date: flight.date)
                    snapshot.flight = pickBestLeg(status.data?.flights) ?? snapshot.flight
                    sourcePullTime = TimeFmt.parseISO(status.pullTime)
                }
            }
            // The freshest phase truth (live layer when present, else the
            // milestone-derived phase) is the single source of truth: a
            // stored brief that disagrees no longer describes reality.
            reconcileBrief(&snapshot)

            // Same-day gate: /api/brief deliberately skips the equipment chain
            // beyond ~12h out, and the chain pull costs paid FlightAware
            // queries — mirror that gate here so a distant flight costs 1 paid
            // query per refresh instead of 3.
            let hours = HorizonGate.hoursToDeparture(snapshot.flight)
            let withinWindow = HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: hours)
            if withinWindow {
                snapshot.chain = (try? await API.flightChain(flight: flight.ident, date: flight.date))?.data
                    ?? snapshot.chain
            }

            // Phase 2 — free feeds keyed by the airports we now know.
            var airports: [String] = []
            if let origin = snapshot.flight?.originIcao { airports.append(origin) }
            if let dest = snapshot.flight?.destIcao, !airports.contains(dest) { airports.append(dest) }

            if !airports.isEmpty {
                let destIcao = snapshot.flight?.destIcao
                async let faaTask = API.faaStatus(icaos: airports)
                async let metarTask = API.metar(icaos: airports)
                async let tafTask = API.taf(icaos: airports)
                async let lightningTask: LightningEnvelope? = {
                    // Lightning is a right-now phenomenon — signal-less at
                    // long horizons, so don't even fetch it there.
                    guard withinWindow, let destIcao else { return nil }
                    return try? await API.lightning(icao: destIcao)
                }()

                let originIcao = snapshot.flight?.originIcao
                // TCF is the FAA's own convective product — free, route-scoped,
                // and only meaningful inside the same-day window (it forecasts
                // 2–6h ahead). Reference data: it never feeds the verdict.
                async let convectiveTask: TcfEnvelope? = {
                    guard withinWindow, let originIcao, let destIcao else { return nil }
                    return try? await API.convectiveForecast(originIcao: originIcao, destIcao: destIcao)
                }()
                // International SIGMETs cover only what the CONUS sigmet feed
                // can't — fetching them for a domestic pair would duplicate it.
                async let isigmetTask: [InternationalSigmet]? = {
                    guard withinWindow,
                          HorizonGate.routeLeavesConus(origin: originIcao, dest: destIcao) else { return nil }
                    return try? await API.internationalSigmets()
                }()

                snapshot.faa = (try? await faaTask)?.data ?? snapshot.faa
                snapshot.metar = (try? await metarTask)?.data ?? snapshot.metar
                snapshot.taf = (try? await tafTask)?.data ?? snapshot.taf
                if let convective = await convectiveTask {
                    snapshot.convective = convective
                }
                if let advisories = await isigmetTask {
                    snapshot.internationalSigmets = InternationalSigmet.inRegion(
                        of: airports, advisories: advisories)
                }
                if let lightning = await lightningTask {
                    snapshot.lightning = FlightSnapshot.LightningWrapper(
                        airport: lightning.airport,
                        strikesWithin5nm: lightning.strikesWithin5nm,
                        totalStrikes: lightning.totalStrikes,
                        rampClosureRisk: lightning.rampClosureRisk,
                        activityLevel: lightning.activityLevel)
                }
            }

            applyAssessment(for: flight, snapshot: &snapshot)
            // Freshness renders from the SOURCE pull time, never receipt time.
            snapshot.lastRefreshed = sourcePullTime ?? Date()
        } catch {
            snapshot.refreshError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            print("[Store] refresh \(flight.id) failed: \(error)")
        }

        // Lost-update guard: runBrief() may have landed a fresher brief while
        // this refresh awaited its network calls — the whole-snapshot write
        // below must never clobber it. Newer runAt wins; the adopted brief is
        // then reconciled against the fresh phase truth like any other.
        if let latest = snapshots[flight.id]?.brief,
           latest.runAt > (snapshot.brief?.runAt ?? .distantPast) {
            snapshot.brief = latest
            reconcileBrief(&snapshot)
        }
        snapshots[flight.id] = snapshot
        persist()
    }

    /// Reconciles the stored brief with the freshest phase truth — the
    /// server's live layer when present, else the phase derived from actual_*
    /// milestones (kept as the guard for offline/stale/error states). On
    /// disagreement the brief is describing a past state: adopt the truth
    /// phase, drop its taxi/position enrichment (they described the old
    /// phase), force the stale treatment, and promote reported actual_* times
    /// over predicted slots so a future "Arrival" never renders after the
    /// flight has arrived.
    private func reconcileBrief(_ snapshot: inout FlightSnapshot) {
        guard var brief = snapshot.brief else { return }
        let truthPhase: BriefPhase? = snapshot.live?.phase
            ?? snapshot.flight.map { FlightPhaseDerivation.minimalBriefPhase(for: $0) }
        guard let truthPhase else { return }
        // A brief without a phase block predates phase support — it implicitly
        // describes a pre-departure flight.
        let briefCode = brief.phase?.code ?? DerivedFlightPhase.preGate.rawValue
        if briefCode != truthPhase.code {
            brief.phase = truthPhase
            brief.taxi = nil
            brief.position = nil
            brief.contradictedByLiveData = true
        }
        if let leg = snapshot.flight {
            brief.predictedTimes = FlightPhaseDerivation.reconciledPredictions(
                brief.predictedTimes, with: leg)
        }
        snapshot.brief = brief
    }

    /// Picks the leg that matches best: prefer one that hasn't arrived yet.
    private func pickBestLeg(_ legs: [AeroFlight]?) -> AeroFlight? {
        guard let legs, !legs.isEmpty else { return nil }
        return legs.first { $0.actualIn == nil && $0.cancelled != true } ?? legs.first
    }

    // MARK: - Pre-flight brief

    /// Runs /api/brief for one flight (2–4 paid queries — strictly user-
    /// initiated, never polled) and persists the verdict. The AI narrative is
    /// written in the background afterwards; the deterministic verdict never
    /// waits for it.
    func runBrief(for flight: TrackedFlight) async throws {
        guard !briefing.contains(flight.id) else { return }
        briefing.insert(flight.id)
        defer { briefing.remove(flight.id) }

        let envelope = try await API.brief(flight: flight.ident, date: flight.date)
        var snapshot = snapshots[flight.id] ?? FlightSnapshot()
        snapshot.brief = StoredBrief(envelope: envelope)
        // Re-run the signal engine immediately so sources the brief excluded
        // stop driving signals, alerts, and the risk color.
        applyAssessment(for: flight, snapshot: &snapshot)
        snapshots[flight.id] = snapshot
        persist()

        if let payload = envelope.llmPayload {
            let flightId = flight.id
            narrativePending.insert(flightId)
            Task {
                do {
                    let text = try await NarrativeService.narrative(for: payload)
                    self.snapshots[flightId]?.brief?.narrative = text
                } catch {
                    print("[Store] narrative for \(flightId) failed: \(error.localizedDescription)")
                    self.snapshots[flightId]?.brief?.narrativeFailed = true
                }
                self.narrativePending.remove(flightId)
                self.persist()
            }
        }
    }

    /// Sources the last brief flagged as signal-less at its horizon. Honored
    /// only while the flight is still on the same side of the same-day
    /// boundary as when the brief ran — once the flight moves inside 12h those
    /// sources go live again and a stale exclusion must not mute them.
    private func activeExcludedSources(_ brief: StoredBrief?) -> Set<String> {
        guard let brief, !brief.sourcesExcluded.isEmpty else { return [] }
        let sideAtRun = HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: brief.hoursToDeparture)
        let sideNow = HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: brief.hoursToDepartureNow)
        guard sideAtRun == sideNow else { return [] }
        return Set(brief.sourcesExcluded.keys)
    }

    // MARK: - Alerts

    private func applyAssessment(for flight: TrackedFlight, snapshot: inout FlightSnapshot) {
        let previous = snapshot.assessment
        let assessment = RiskEngine.evaluate(
            flight: snapshot.flight,
            chain: snapshot.chain,
            faa: snapshot.faa,
            metar: snapshot.metar,
            taf: snapshot.taf,
            lightning: snapshot.lightning,
            hoursToDeparture: HorizonGate.hoursToDeparture(snapshot.flight),
            excludedSources: activeExcludedSources(snapshot.brief))
        snapshot.assessment = assessment

        var newAlerts: [FlightAlert] = []
        let previousKeys = Set(previous?.signals.map(\.key) ?? [])

        // Aggressive mode: every newly fired signal becomes an alert.
        for signal in assessment.signals where !previousKeys.contains(signal.key) {
            newAlerts.append(FlightAlert(
                flightKey: flight.id, ident: flight.ident,
                title: signal.title, message: signal.detail,
                level: signal.level, icon: signal.icon))
        }

        // Signal-level transitions (including improvements) also alert.
        if let previous, previous.level != assessment.level {
            let improved = assessment.level.rank < previous.level.rank
            newAlerts.append(FlightAlert(
                flightKey: flight.id, ident: flight.ident,
                title: improved
                    ? "\(flight.ident) signals eased to \(assessment.level.rawValue)"
                    : "\(flight.ident) signals elevated to \(assessment.level.rawValue)",
                message: improved
                    ? "Live signals improved from \(previous.level.rawValue)."
                    : "Escalated from \(previous.level.rawValue) — open the flight for details.",
                level: assessment.level,
                icon: improved ? "trending-down" : "trending-up",
                isImprovement: improved))
        } else if previous == nil, assessment.level != .low {
            newAlerts.append(FlightAlert(
                flightKey: flight.id, ident: flight.ident,
                title: "\(flight.ident) already showing \(assessment.level.rawValue) signals",
                message: "Live signals were elevated when tracking started.",
                level: assessment.level, icon: "flag"))
        }

        if !newAlerts.isEmpty {
            alerts.insert(contentsOf: newAlerts, at: 0)
            if alerts.count > 300 { alerts = Array(alerts.prefix(300)) }
            Haptics.warning()
            // Reach the closed-in-pocket phone too: local notifications,
            // grouped per flight, severity-mapped. Improvements never post.
            for alert in newAlerts {
                NotificationService.post(alert)
            }
        }
    }

    func markAllAlertsRead() {
        for index in alerts.indices { alerts[index].isRead = true }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        save(flights, key: Keys.flights)
        save(snapshots, key: Keys.snapshots)
        save(alerts, key: Keys.alerts)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
