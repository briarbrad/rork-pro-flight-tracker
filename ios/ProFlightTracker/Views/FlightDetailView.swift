import SwiftUI

/// Phase-adaptive flight report. The screen reads the freshest phase truth
/// (live layer → brief fallback → milestone-derived guard) and organises
/// itself around it:
/// - Pre-flight (>2h out): verdict + predicted departure first; live detail
///   (aircraft chain, conditions, map) collapsed behind disclosure headers.
/// - Day-of / in-air: next event first, live map promoted to slot 2,
///   EDCT above the predicted-times grid, destination conditions next.
/// - Landed / cancelled: one compact closure card + a collapsed flight
///   record — history is never restated as prediction.
struct FlightDetailView: View {
    @Environment(AppStore.self) private var store
    let flight: TrackedFlight

    @State private var showingMap: Bool = false
    @State private var popup: DetailPopup?
    @State private var jargon: GlossaryEntry?
    @State private var inboundToShow: AeroFlight?

    private var snapshot: FlightSnapshot? { store.snapshots[flight.id] }
    private var leg: AeroFlight? { snapshot?.flight }
    private var live: StoredLive? { snapshot?.live }
    private var brief: StoredBrief? { snapshot?.brief }

    private var hoursToDeparture: Double? { HorizonGate.hoursToDeparture(leg) }

    /// Every time on this screen is shown in the zone of the airport it belongs
    /// to — departure facts in the origin's, arrival facts in the destination's.
    private var zones: FlightZones {
        FlightZones.resolve(flight: leg,
                            brief: live?.timezones ?? brief?.timezones)
    }

    // MARK: - Phase truth & screen mode

    /// The freshest phase on file — the single source of truth the screen is
    /// organised around. Live layer wins on every refresh; the brief's phase
    /// only renders before the first live pull; the milestone-derived guard
    /// covers the no-data case.
    private var truthPhase: BriefPhase? {
        if let phase = live?.phase { return phase }
        if live == nil, let phase = brief?.phase { return phase }
        return leg.map { FlightPhaseDerivation.minimalBriefPhase(for: $0) }
    }

    private enum ScreenMode { case preFlight, dayOf, closed }

    private var mode: ScreenMode {
        if let phase = truthPhase {
            if phase.isOver { return .closed }
            if phase.isEnRoute { return .dayOf }
        }
        if let hours = hoursToDeparture, hours > 2 { return .preFlight }
        return .dayOf
    }

    // MARK: - Hero inputs

    /// Taxi assessment from the live layer; brief fallback only pre-live.
    private var heroTaxi: BriefTaxi? {
        live?.taxi ?? (live == nil ? brief?.taxi : nil)
    }

    /// The live layer carries no position block (one query, no ADS-B) — the
    /// brief's position is enrichment on it, but only while the brief is
    /// fresh and still describes the same phase.
    private var heroPosition: BriefPosition? {
        guard let brief, !brief.isStale,
              brief.phase?.code == truthPhase?.code else { return nil }
        return brief.position
    }

    private var heroNextEventEntry: BriefPredictedTime? {
        live?.nextEventPredictedTime ?? brief?.nextEventPredictedTime
    }

    /// SOURCE-pull anchor for the hero's countdowns and freshness caption.
    private var heroAsOf: Date? {
        live?.fetchedAt ?? snapshot?.lastRefreshed ?? brief?.runAt
    }

    /// Older than its refresh window — the hero caption turns amber.
    private var heroIsStale: Bool {
        live?.isStale ?? (snapshot?.autoRefreshDue ?? false)
    }

    /// Signals about the flight itself and its aircraft chain. Shown only
    /// until a brief provides effects[] — after that, the server's cause →
    /// effect list is the sole explanation on this screen.
    private var flightSignals: [RiskSignal] {
        (snapshot?.assessment?.signals ?? []).filter {
            $0.key.hasPrefix("flight.") || $0.key.hasPrefix("chain.")
        }
    }

    private var briefHasEffects: Bool { brief?.hasEffects == true }

    /// Current status-scope effects from the cheap live refresh — the
    /// evidence that stays true even after the brief narrative goes stale.
    private var liveEffects: [BriefEffect] { live?.effects ?? [] }

    /// A stale brief must never suppress CURRENT live evidence: when the
    /// narrative is out of date but the live layer observed effects, they
    /// surface under their own "Since your brief" card.
    private var showLiveEffectsSection: Bool {
        brief != nil && brief?.isStale == true && !liveEffects.isEmpty
    }

    private var conditionsTitle: String {
        var names: [String] = []
        if let origin = leg?.originDisplay, origin != "???" { names.append(origin) }
        if let dest = leg?.destDisplay, dest != "???", !names.contains(dest) { names.append(dest) }
        guard !names.isEmpty else { return "Conditions right now" }
        return "Conditions at \(names.joined(separator: " & ")) right now"
    }

    /// Current conditions are reference data, never flight risk — effects[]
    /// carries the flight-level meaning. At long horizons, note staleness too.
    private var conditionsNote: String? {
        guard let hours = hoursToDeparture, hours > HorizonGate.sameDayWindowHours else { return nil }
        return "Live snapshot ~\(Int(hours.rounded()))h before departure — weather and FAA programs this far out will usually clear or change before your flight. They don't feed the assessment above."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // ONE banner for offline/refresh failures — cards below keep
                // rendering last-known data with their freshness captions.
                if let error = snapshot?.refreshError {
                    GlobalRefreshBanner(message: error) {
                        Task { await store.refresh(flight) }
                    }
                }

                switch mode {
                case .preFlight: preFlightLayout
                case .dayOf: dayOfLayout
                case .closed: closedLayout
                }
            }
            .padding(.horizontal, 16)
        }
        // Keeps the floating tab bar from covering the last card.
        .contentMargins(.bottom, 24, for: .scrollContent)
        .background(Theme.canvas)
        .navigationTitle(flight.ident)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    Task { await store.refresh(flight) }
                } label: {
                    if store.refreshing.contains(flight.id) {
                        ProgressView().controlSize(.small).tint(Theme.teal)
                    } else {
                        LucideIcon(name: "refresh-cw", size: 17, fallback: "arrow.clockwise")
                            .foregroundStyle(Theme.teal)
                    }
                }
                .accessibilityLabel("Refresh flight data")
            }
        }
        .fullScreenCover(isPresented: $showingMap) {
            LiveMapView(flight: flight,
                        initialPosition: snapshot?.chain?.aircraftPosition,
                        registration: snapshot?.chain?.tailNumber ?? leg?.registration)
        }
        .fullScreenCover(item: $popup) { DetailPopupHost(popup: $0) }
        // Glossary definitions are a half-height system sheet — quick to
        // glance, quick to dismiss.
        .sheet(item: $jargon) { JargonSheet(entry: $0) }
        .navigationDestination(item: $inboundToShow) { inbound in
            InboundFlightView(inbound: inbound)
        }
        .glossaryLinkHandler { entry in
            Haptics.tap()
            jargon = entry
        }
        .task {
            // Staleness gate driven by the server's refresh_after_seconds
            // (null = flight is final, never refetch). Not a poll — fires
            // once per screen-open.
            if snapshot?.autoRefreshDue ?? true {
                await store.refresh(flight)
            }
        }
    }

    // MARK: - Pre-flight (>2h out): schedule-first, live detail collapsed

    @ViewBuilder
    private var preFlightLayout: some View {
        heroCard
        edctBannerView
        predictedTimesCard
        forecastWindows
        BriefSection(flight: flight)
        signalsSection
        if snapshot?.chain != nil {
            CollapsibleSection(icon: "link", title: "Your aircraft",
                               subtitle: "Inbound leg and turn time") {
                chainSection(embedded: true)
            }
        }
        if snapshot?.chain?.aircraftPosition != nil {
            CollapsibleSection(icon: "map", title: "Live position") {
                mapSection(embedded: true)
            }
        }
        if leg?.originIcao != nil || leg?.destIcao != nil {
            CollapsibleSection(icon: "cloud-sun", title: "Airport conditions",
                               subtitle: "Reference only at this horizon") {
                weatherSection(embedded: true)
                EnrouteHazardsSection(convective: snapshot?.convective,
                                      internationalSigmets: snapshot?.internationalSigmets,
                                      embedded: true)
            }
        }
        // Already horizon-gated: locks itself beyond the same-day window.
        OpsSection(originIcao: leg?.originIcao,
                   destIcao: leg?.destIcao,
                   hoursToDeparture: hoursToDeparture)
        NarrativeSection(flight: flight)
        alertHistory(embedded: false)
    }

    // MARK: - Day-of / in-air: next event first, map promoted

    @ViewBuilder
    private var dayOfLayout: some View {
        heroCard
        // Live map promoted to slot 2 (renders only when a position exists).
        mapSection(embedded: false)
        edctBannerView
        predictedTimesCard
        weatherSection(embedded: false)
        forecastWindows
        BriefSection(flight: flight)
        signalsSection
        EnrouteHazardsSection(convective: snapshot?.convective,
                              internationalSigmets: snapshot?.internationalSigmets)
        chainSection(embedded: false)
        OpsSection(originIcao: leg?.originIcao,
                   destIcao: leg?.destIcao,
                   hoursToDeparture: hoursToDeparture)
        NarrativeSection(flight: flight)
        alertHistory(embedded: false)
    }

    // MARK: - Landed / cancelled: closure card + collapsed record

    @ViewBuilder
    private var closedLayout: some View {
        // PredictedTimesCard is suppressed entirely here — history is never
        // restated as prediction.
        FlightClosureCard(leg: leg,
                          phase: truthPhase,
                          zones: zones,
                          lastRefreshed: snapshot?.lastRefreshed)
        CollapsibleSection(icon: "archive", title: "Flight record",
                           subtitle: "Actual times and alert history") {
            FlightRecordCard(leg: leg, zones: zones, embedded: true)
            alertHistory(embedded: true)
        }
    }

    // MARK: - Shared building blocks

    private var heroCard: some View {
        FlightHeroCard(leg: leg,
                       phase: truthPhase,
                       taxi: heroTaxi,
                       position: heroPosition,
                       nextEventEntry: heroNextEventEntry,
                       brief: brief,
                       live: live,
                       zones: zones,
                       asOf: heroAsOf,
                       isStale: heroIsStale) {
            Task { await store.refresh(flight) }
        }
    }

    /// FAA-assigned wheels-up slot — the top fact when present, always ABOVE
    /// the predicted-times grid. The live layer re-attaches cached EDCTs, so
    /// it wins here too.
    @ViewBuilder
    private var edctBannerView: some View {
        if let edct = live?.predictedTimes?.edct ?? brief?.predictedTimes?.edct,
           edct.edct != nil {
            EdctBanner(edct: edct, originZone: zones.origin)
        }
    }

    /// Server-predicted times — live layer wins on every refresh; the brief
    /// only feeds this before the first live pull.
    @ViewBuilder
    private var predictedTimesCard: some View {
        if let live, let times = live.predictedTimes {
            PredictedTimesCard(times: times,
                               timezones: live.timezones ?? brief?.timezones,
                               zones: zones,
                               isStale: live.isStale, runAt: live.fetchedAt,
                               staleVerb: "refresh") {
                Task { await store.refresh(flight) }
            }
        } else if let brief, let times = brief.predictedTimes {
            PredictedTimesCard(times: times, timezones: brief.timezones, zones: zones,
                               isStale: brief.isStale, runAt: brief.runAt) {
                Task { try? await store.runBrief(for: flight) }
            }
        }
    }

    /// Terminal forecast in the ±60 min window around the predicted times —
    /// the only weather block that can move the verdict.
    @ViewBuilder
    private var forecastWindows: some View {
        if let windows = brief?.tafWindows, brief?.hasForecastWindows == true {
            ForecastWindowSection(windows: windows)
        }
    }

    /// Once a brief supplies effects[], those replace the client signal list
    /// as the explanation on this screen — but only while the brief is
    /// current. A STALE brief's effects never hide live evidence: current
    /// live-layer effects render under "Since your brief" so the user still
    /// sees what's true right now.
    @ViewBuilder
    private var signalsSection: some View {
        if showLiveEffectsSection {
            liveEffectsCard
        }
        if !briefHasEffects {
            SignalListSection(title: "Flight status signals",
                              icon: "activity",
                              caption: "From the airline's status feed and this aircraft's own chain. Run the brief for the full cause → effect picture.",
                              signals: flightSignals) { signal in
                Haptics.tap()
                popup = .riskSignal(signal)
            }
        }
    }

    /// Live-layer effects shown when the brief has gone stale: clearly
    /// labeled as what the status feed observed AFTER the brief ran, with
    /// its own freshness caption anchored on the live pull.
    private var liveEffectsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "activity", title: "Since your brief")
            Text("Your brief's narrative is out of date, but these effects are from the latest status pull — they reflect the flight right now.")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            EffectsList(effects: liveEffects)
            if let asOf = live?.fetchedAt {
                FreshnessCaption(asOf: asOf,
                                 prefix: "Status pulled",
                                 isStale: live?.isStale ?? false,
                                 staleHint: "refresh for the current picture.") {
                    Task { await store.refresh(flight) }
                }
            }
        }
        .cardStyle()
    }

    /// `embedded: true` when rendered inside a CollapsibleSection's card —
    /// the section drops its own card shell and redundant title so the
    /// disclosure header and content read as one surface.
    @ViewBuilder
    private func chainSection(embedded: Bool) -> some View {
        if let chain = snapshot?.chain {
            // The inbound leg lands at this flight's origin, so its ETA
            // reads in the origin's local time.
            ChainSection(chain: chain, arrivalZone: zones.origin,
                         embedded: embedded) { inbound in
                Haptics.tap()
                inboundToShow = inbound
            }
        }
    }

    private func mapSection(embedded: Bool) -> some View {
        MapPreviewSection(position: snapshot?.chain?.aircraftPosition,
                          flightIdent: flight.ident,
                          embedded: embedded) {
            Haptics.tap()
            showingMap = true
        }
    }

    private func weatherSection(embedded: Bool) -> some View {
        WeatherSection(leg: leg,
                       metar: snapshot?.metar,
                       taf: snapshot?.taf,
                       faa: snapshot?.faa,
                       title: conditionsTitle,
                       horizonNote: conditionsNote,
                       embedded: embedded,
                       onOpenWeather: { icao in
                           Haptics.tap()
                           popup = .weather(icao: icao,
                                            metar: snapshot?.metar?[icao],
                                            taf: snapshot?.taf?[icao],
                                            faa: snapshot?.faa?[icao])
                       },
                       onOpenFaa: { icao in
                           guard let record = snapshot?.faa?[icao] else { return }
                           Haptics.tap()
                           popup = .faaPrograms(icao: icao, record: record)
                       })
    }

    // MARK: - Alert history

    /// `embedded: true` inside the flight-record collapsible — keeps the
    /// sub-header but drops the card shell.
    @ViewBuilder
    private func alertHistory(embedded: Bool) -> some View {
        let flightAlerts = store.alerts(for: flight.id)
        if !flightAlerts.isEmpty {
            let content = VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "bell-ring", title: "Alert history")
                ForEach(flightAlerts.prefix(10)) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        LucideIcon(name: alert.icon, size: 14, fallback: "bell")
                            .foregroundStyle(alert.level.color)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(TimeFmt.relative(alert.createdAt))
                                .font(.caption2)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                    }
                }
            }
            if embedded {
                content
            } else {
                content.cardStyle()
            }
        }
    }
}

/// Shared section header row with a Lucide icon.
struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            LucideIcon(name: icon, size: 16, fallback: "circle")
                .foregroundStyle(Theme.teal)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}
