import SwiftUI

/// Full flight report: status header, pre-flight brief (the only flight-level
/// verdict), live flight signals, inbound chain, map preview, current airport
/// conditions, horizon-gated ops deep-dive, and alert history.
struct FlightDetailView: View {
    @Environment(AppStore.self) private var store
    let flight: TrackedFlight

    @State private var showingMap: Bool = false
    @State private var popup: DetailPopup?
    @State private var inboundToShow: AeroFlight?

    private var snapshot: FlightSnapshot? { store.snapshots[flight.id] }
    private var leg: AeroFlight? { snapshot?.flight }

    private var hoursToDeparture: Double? { HorizonGate.hoursToDeparture(leg) }

    /// Every time on this screen is shown in the zone of the airport it belongs
    /// to — departure facts in the origin's, arrival facts in the destination's.
    private var zones: FlightZones {
        FlightZones.resolve(flight: leg, brief: snapshot?.brief?.timezones)
    }

    /// Signals about the flight itself and its aircraft chain. Shown only
    /// until a brief provides effects[] — after that, the server's cause →
    /// effect list is the sole explanation on this screen.
    private var flightSignals: [RiskSignal] {
        (snapshot?.assessment?.signals ?? []).filter {
            $0.key.hasPrefix("flight.") || $0.key.hasPrefix("chain.")
        }
    }

    private var briefHasEffects: Bool { snapshot?.brief?.hasEffects == true }

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
                headerCard

                if let error = snapshot?.refreshError {
                    errorBanner(error)
                }

                BriefSection(flight: flight)

                // Once a brief supplies effects[], those replace the client
                // signal list as the explanation on this screen.
                if !briefHasEffects {
                    SignalListSection(title: "Flight status signals",
                                      icon: "activity",
                                      caption: "From the airline's status feed and this aircraft's own chain. Run the brief for the full cause → effect picture.",
                                      signals: flightSignals) { signal in
                        Haptics.tap()
                        popup = .riskSignal(signal)
                    }
                }

                // Terminal forecast in the ±60 min window around the predicted
                // times — the only weather block that can move the verdict.
                if let windows = snapshot?.brief?.tafWindows,
                   snapshot?.brief?.hasForecastWindows == true {
                    ForecastWindowSection(windows: windows)
                }

                EnrouteHazardsSection(convective: snapshot?.convective,
                                      internationalSigmets: snapshot?.internationalSigmets)

                if let chain = snapshot?.chain {
                    // The inbound leg lands at this flight's origin, so its ETA
                    // reads in the origin's local time.
                    ChainSection(chain: chain, arrivalZone: zones.origin) { inbound in
                        Haptics.tap()
                        inboundToShow = inbound
                    }
                }

                MapPreviewSection(position: snapshot?.chain?.aircraftPosition,
                                  flightIdent: flight.ident) {
                    Haptics.tap()
                    showingMap = true
                }

                WeatherSection(leg: leg,
                               metar: snapshot?.metar,
                               taf: snapshot?.taf,
                               faa: snapshot?.faa,
                               title: conditionsTitle,
                               horizonNote: conditionsNote,
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

                OpsSection(originIcao: leg?.originIcao,
                           destIcao: leg?.destIcao,
                           hoursToDeparture: hoursToDeparture)

                NarrativeSection(flight: flight)

                alertHistory
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
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
        .navigationDestination(item: $inboundToShow) { inbound in
            InboundFlightView(inbound: inbound)
        }
        .glossaryLinkHandler { entry in
            Haptics.tap()
            popup = .jargon(entry)
        }
        .task {
            let stale = (snapshot?.lastRefreshed.map { Date().timeIntervalSince($0) > 120 }) ?? true
            if stale {
                await store.refresh(flight)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(leg?.originCity ?? leg?.originDisplay ?? "—") → \(leg?.destCity ?? leg?.destDisplay ?? "—")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(leg?.status ?? "Awaiting data")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                // The flight-level verdict comes exclusively from /api/brief.
                if let brief = snapshot?.brief {
                    BriefVerdictBadge(brief: brief)
                }
            }

            Divider().overlay(Theme.hairline)

            HStack(alignment: .top) {
                timeColumn(title: leg?.originDisplay ?? "DEP",
                           gate: gateText(leg?.gateOrigin, leg?.terminalOrigin),
                           scheduled: leg?.scheduledOut,
                           estimated: leg?.estimatedOut,
                           actual: leg?.actualOut,
                           zone: zones.origin,
                           alignment: .leading)
                Spacer()
                VStack(spacing: 4) {
                    LucideIcon(name: "plane", size: 18, fallback: "airplane")
                        .foregroundStyle(Theme.teal)
                    if let progress = leg?.progressPercent, progress > 0 {
                        Text("\(Int(progress))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.teal)
                    }
                    if let tail = leg?.registration {
                        Text(tail)
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer()
                timeColumn(title: leg?.destDisplay ?? "ARR",
                           gate: gateText(leg?.gateDestination, leg?.terminalDestination),
                           scheduled: leg?.scheduledIn,
                           estimated: leg?.estimatedIn,
                           actual: leg?.actualIn,
                           zone: zones.destination,
                           alignment: .trailing)
            }

            if let refreshed = snapshot?.lastRefreshed {
                HStack(spacing: 4) {
                    LucideIcon(name: "history", size: 11, fallback: "clock")
                    Text("Updated \(TimeFmt.relative(refreshed))")
                }
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
            }
        }
        .cardStyle()
    }

    private func gateText(_ gate: String?, _ terminal: String?) -> String? {
        switch (gate, terminal) {
        case let (gate?, terminal?): return "T\(terminal) · Gate \(gate)"
        case let (gate?, nil): return "Gate \(gate)"
        case let (nil, terminal?): return "Terminal \(terminal)"
        default: return nil
        }
    }

    private func timeColumn(title: String, gate: String?, scheduled: String?,
                            estimated: String?, actual: String?, zone: TimeZone?,
                            alignment: HorizontalAlignment) -> some View {
        let effective = actual ?? estimated
        let shown = effective ?? scheduled
        return VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
            if let gate {
                Text(gate)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(TimeFmt.clock(shown, zone: zone))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(slipColor(scheduled: scheduled, effective: effective))
                if let label = TimeFmt.zoneLabel(zone, atISO: shown) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            // An arrival on the next local day is a fact worth stating outright.
            if let dayLabel = crossesDayLabel(shown, zone: zone) {
                Text(dayLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.teal)
            }
            if let effective, let sched = scheduled,
               TimeFmt.parseISO(effective) != TimeFmt.parseISO(sched) {
                Text("Sched \(TimeFmt.clock(sched, zone: zone))")
                    .font(.caption2)
                    .strikethrough()
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    /// "Tue Aug 18" when this time falls on a different local day than the
    /// origin's departure day — the overnight-arrival case.
    private func crossesDayLabel(_ iso: String?, zone: TimeZone?) -> String? {
        let departure = leg?.actualOut ?? leg?.estimatedOut ?? leg?.scheduledOut
        guard iso != departure,
              TimeFmt.crossesLocalDay(iso, zone: zone,
                                      reference: departure, referenceZone: zones.origin) else {
            return nil
        }
        return TimeFmt.weekdayDate(iso, zone: zone)
    }

    private func slipColor(scheduled: String?, effective: String?) -> Color {
        guard let sched = TimeFmt.parseISO(scheduled),
              let eff = TimeFmt.parseISO(effective) else { return Theme.ink }
        let slip = eff.timeIntervalSince(sched) / 60
        if slip >= 45 { return Theme.red }
        if slip >= 15 { return Theme.gold }
        return Theme.ink
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            LucideIcon(name: "wifi-off", size: 16, fallback: "wifi.slash")
            Text(message)
                .font(.caption)
        }
        .foregroundStyle(Theme.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Alert history

    private var alertHistory: some View {
        let flightAlerts = store.alerts(for: flight.id)
        return Group {
            if !flightAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
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
                .cardStyle()
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
