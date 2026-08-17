import SwiftUI

/// Full detail page for the inbound aircraft's previous leg. Renders instantly
/// from the chain data, then makes ONE careful AeroAPI status pull plus free
/// weather feeds — and lets the user add the leg to their watchlist.
struct InboundFlightView: View {
    @Environment(AppStore.self) private var store

    let inbound: AeroFlight

    @State private var refreshedLeg: AeroFlight?
    @State private var metar: [String: MetarObservation] = [:]
    @State private var taf: [String: TafReport] = [:]
    @State private var faa: [String: FaaAirportStatus] = [:]
    @State private var assessment: RiskAssessment?
    @State private var isLoading: Bool = false
    @State private var hasLoaded: Bool = false
    @State private var popup: DetailPopup?
    @State private var isAdding: Bool = false
    @State private var addMessage: String?
    @State private var addSucceeded: Bool = false

    private var flight: AeroFlight { refreshedLeg ?? inbound }

    /// This leg's own two zones — its departure and arrival airports.
    private var zones: FlightZones { FlightZones.resolve(flight: flight) }

    private var isAlreadyTracked: Bool {
        guard let ident = flight.ident else { return false }
        return store.flights.contains { $0.ident == ident }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                watchlistCard
                SignalListSection(title: "Signals on this leg",
                                  icon: "activity",
                                  signals: assessment?.signals ?? [],
                                  emptyText: assessment == nil ? nil : "Nothing firing on this leg right now.") { signal in
                    Haptics.tap()
                    popup = .riskSignal(signal)
                }
                WeatherSection(leg: flight,
                               metar: metar.isEmpty ? nil : metar,
                               taf: taf.isEmpty ? nil : taf,
                               faa: faa.isEmpty ? nil : faa,
                               onOpenWeather: { icao in
                                   Haptics.tap()
                                   popup = .weather(icao: icao,
                                                    metar: metar[icao],
                                                    taf: taf[icao],
                                                    faa: faa[icao])
                               },
                               onOpenFaa: { icao in
                                   guard let record = faa[icao] else { return }
                                   Haptics.tap()
                                   popup = .faaPrograms(icao: icao, record: record)
                               })
                footnote
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Theme.canvas)
        .navigationTitle(flight.ident ?? "Inbound")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $popup) { DetailPopupHost(popup: $0) }
        .glossaryLinkHandler { entry in
            Haptics.tap()
            popup = .jargon(entry)
        }
        .task { await load() }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        LucideIcon(name: "link", size: 11, fallback: "link")
                        Text("Inbound aircraft leg")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.teal)
                    Text("\(flight.originCity ?? flight.originDisplay) → \(flight.destCity ?? flight.destDisplay)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(flight.status ?? "Awaiting data")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                if let assessment {
                    RiskBadge(level: assessment.level)
                } else if isLoading {
                    ProgressView().controlSize(.small).tint(Theme.teal)
                }
            }

            HStack(spacing: 8) {
                if let tail = flight.registration {
                    chip(icon: "plane", text: tail)
                }
                if let type = flight.aircraftType {
                    chip(icon: "info", text: type)
                }
                if let progress = flight.progressPercent, progress > 0 {
                    chip(icon: "gauge", text: "\(Int(progress))% flown")
                }
                Spacer()
            }

            Divider().overlay(Theme.hairline)

            HStack(alignment: .top) {
                timeColumn(title: flight.originDisplay,
                           scheduled: flight.scheduledOut,
                           estimated: flight.estimatedOut,
                           actual: flight.actualOut,
                           zone: zones.origin,
                           alignment: .leading)
                Spacer()
                LucideIcon(name: "plane", size: 18, fallback: "airplane")
                    .foregroundStyle(Theme.teal)
                    .padding(.top, 4)
                Spacer()
                timeColumn(title: flight.destDisplay,
                           scheduled: flight.scheduledIn,
                           estimated: flight.estimatedIn,
                           actual: flight.actualIn,
                           zone: zones.destination,
                           alignment: .trailing)
            }
        }
        .cardStyle()
    }

    private func timeColumn(title: String, scheduled: String?, estimated: String?,
                            actual: String?, zone: TimeZone?,
                            alignment: HorizontalAlignment) -> some View {
        let effective = actual ?? estimated
        let shown = effective ?? scheduled
        return VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(TimeFmt.clock(shown, zone: zone))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(slipColor(scheduled: scheduled, effective: effective))
                if let label = TimeFmt.zoneLabel(zone, atISO: shown) {
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Theme.inkSecondary)
                }
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

    private func slipColor(scheduled: String?, effective: String?) -> Color {
        guard let sched = TimeFmt.parseISO(scheduled),
              let eff = TimeFmt.parseISO(effective) else { return Theme.ink }
        let slip = eff.timeIntervalSince(sched) / 60
        if slip >= 45 { return Theme.red }
        if slip >= 15 { return Theme.goldText }
        return Theme.ink
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            LucideIcon(name: icon, size: 11, fallback: "circle")
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.inkSecondary.opacity(0.08))
        .clipShape(.capsule)
    }

    // MARK: - Watchlist button

    private var watchlistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAlreadyTracked || addSucceeded {
                HStack(spacing: 8) {
                    LucideIcon(name: "circle-check", size: 16, fallback: "checkmark.circle")
                        .foregroundStyle(Theme.green)
                    Text(addSucceeded ? "Added to your watchlist." : "Already on your watchlist.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
            } else {
                Button {
                    addToWatchlist()
                } label: {
                    HStack(spacing: 8) {
                        if isAdding {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            LucideIcon(name: "plus", size: 15, fallback: "plus")
                        }
                        Text(isAdding ? "Adding…" : "Track this flight")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.teal)
                    .clipShape(.rect(cornerRadius: 14))
                }
                .disabled(isAdding || flight.ident == nil)

                if let addMessage {
                    Text(addMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                }
            }
        }
        .cardStyle()
    }

    private var footnote: some View {
        HStack(spacing: 6) {
            LucideIcon(name: "leaf", size: 11, fallback: "leaf")
            Text("Refreshed once on open to stay light on paid flight data. Weather updates are free and live.")
                .font(.caption2)
        }
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - Data

    private func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }

        // One careful AeroAPI pull for the freshest status of this leg.
        if let ident = inbound.ident {
            // Date key in the inbound's ORIGIN-local day — the backend matches
            // flights on origin-local date, not UTC.
            let originZone = AirportTimeZones.zone(forAnyOf: inbound.originIcao, inbound.originIata)
            let date = TimeFmt.parseISO(inbound.scheduledOut).map { TimeFmt.apiDate($0, zone: originZone) }
            if let status = try? await API.flightStatus(flight: ident, date: date),
               let legs = status.data?.flights, !legs.isEmpty {
                refreshedLeg = legs.first { $0.faFlightId == inbound.faFlightId }
                    ?? legs.first { $0.actualIn == nil && $0.cancelled != true }
                    ?? legs.first
            }
        }

        // Free feeds for this leg's airports.
        var airports: [String] = []
        if let origin = flight.originIcao { airports.append(origin) }
        if let dest = flight.destIcao, !airports.contains(dest) { airports.append(dest) }

        if !airports.isEmpty {
            async let metarTask = try? API.metar(icaos: airports)
            async let tafTask = try? API.taf(icaos: airports)
            async let faaTask = try? API.faaStatus(icaos: airports)
            let (metarEnv, tafEnv, faaEnv) = await (metarTask, tafTask, faaTask)
            metar = metarEnv?.data ?? [:]
            taf = tafEnv?.data ?? [:]
            faa = faaEnv?.data ?? [:]
        }

        assessment = RiskEngine.evaluate(
            flight: flight,
            chain: nil,
            faa: faa.isEmpty ? nil : faa,
            metar: metar.isEmpty ? nil : metar,
            taf: taf.isEmpty ? nil : taf,
            lightning: nil,
            hoursToDeparture: HorizonGate.hoursToDeparture(flight))
    }

    private func addToWatchlist() {
        guard let ident = flight.ident else { return }
        Haptics.tap()
        isAdding = true
        addMessage = nil
        Task {
            do {
                let date = TimeFmt.parseISO(flight.scheduledOut) ?? Date()
                try await store.addFlight(ident: ident, date: date, intervalMinutes: 30)
                Haptics.success()
                addSucceeded = true
            } catch {
                addMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isAdding = false
        }
    }
}
