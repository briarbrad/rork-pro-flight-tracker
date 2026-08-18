import SwiftUI

/// Airports tab: quick lookup of any airport's weather, FAA status, and RVR.
struct AirportsView: View {
    @State private var query: String = ""
    @State private var lookedUpIcao: String?
    @State private var isLoading: Bool = false
    @State private var metar: MetarObservation?
    @State private var taf: TafReport?
    @State private var faa: FaaAirportStatus?
    @State private var lightning: LightningEnvelope?
    @State private var errorMessage: String?
    /// Last code actually sent to the API — what the error card's Retry
    /// re-runs, independent of whatever the search field says now.
    @State private var lastAttempted: String?
    @State private var recents: [String] = UserDefaults.standard.stringArray(forKey: "pft.recentAirports") ?? []
    @State private var popup: DetailPopup?
    @State private var jargon: GlossaryEntry?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.md - 2) {
                    searchBar

                    if !recents.isEmpty && lookedUpIcao == nil {
                        recentsRow
                    }

                    if isLoading {
                        loadingCard
                    } else if let errorMessage {
                        errorCard(errorMessage)
                    } else if let icao = lookedUpIcao {
                        resultCards(icao: icao)
                    } else {
                        placeholder
                    }
                }
                .padding(.horizontal, Space.md)
            }
            // Keeps the floating tab bar from covering the last card.
            .contentMargins(.bottom, Space.lg, for: .scrollContent)
            .background(Theme.canvas)
            .navigationTitle("Airports")
            .fullScreenCover(item: $popup) { DetailPopupHost(popup: $0) }
            .sheet(item: $jargon) { JargonSheet(entry: $0) }
            .glossaryLinkHandler { entry in
                Haptics.tap()
                jargon = entry
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            LucideIcon(name: "search", size: 16, fallback: "magnifyingglass")
                .foregroundStyle(Theme.inkSecondary)
            TextField("ICAO code — KJFK, EGLL, KATL…", text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .font(.body.weight(.medium))
                .onSubmit { lookup(query) }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    LucideIcon(name: "x", size: 14, fallback: "xmark")
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Button {
                lookup(query)
            } label: {
                Text("Look up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.teal)
                    .clipShape(.capsule)
            }
            .disabled(query.trimmingCharacters(in: .whitespaces).count < 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .cardShadow()
    }

    private var recentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recents, id: \.self) { icao in
                    Button {
                        query = icao
                        lookup(icao)
                    } label: {
                        StatusChip(text: icao, icon: "history", tone: .info)
                    }
                }
            }
        }
        .contentMargins(.horizontal, 2)
    }

    private var placeholder: some View {
        EmptyState(icon: "tower-control",
                   iconFallback: "building.2",
                   title: "Check any airport",
                   message: "Live METAR and TAF, FAA ground stops and delay programs, plus nearby lightning — straight from the engine's free feeds.")
            .padding(.top, 60)
    }

    private var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.teal)
            Text("Pulling live weather and FAA status…")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .cardStyle()
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            InlineNotice(style: .error, message: message)
            if let lastAttempted {
                PrimaryActionButton(title: "Retry \(lastAttempted)",
                                    icon: "refresh-cw",
                                    iconFallback: "arrow.clockwise") {
                    lookup(lastAttempted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func resultCards(icao: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(icon: "tower-control", title: icao)
            AirportWeatherCard(icao: icao, metar: metar, taf: taf, faa: faa,
                               onOpenWeather: {
                                   Haptics.tap()
                                   popup = .weather(icao: icao, metar: metar, taf: taf, faa: faa)
                               },
                               onOpenFaa: {
                                   guard let faa else { return }
                                   Haptics.tap()
                                   popup = .faaPrograms(icao: icao, record: faa)
                               })

            if let lightning, lightning.error == nil {
                HStack(spacing: 8) {
                    LucideIcon(name: "zap", size: 14, fallback: "bolt")
                        .foregroundStyle((lightning.strikesWithin5nm ?? 0) > 0 ? Theme.gold : Theme.green)
                    Text(lightningSummary(lightning))
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            if let taf, let periods = taf.forecastPeriods, !periods.isEmpty {
                tafTimeline(periods, zone: AirportTimeZones.zone(for: icao))
            }
        }
        .cardStyle()
    }

    private func lightningSummary(_ lightning: LightningEnvelope) -> String {
        let total = lightning.totalStrikes ?? 0
        if total == 0 { return "No lightning detected nearby." }
        return "\(total) strikes nearby, \(lightning.strikesWithin5nm ?? 0) within 5 nm — ramp risk \(lightning.rampClosureRisk ?? "unknown")."
    }

    /// Forecast times read in the airport's own local time — that's the clock a
    /// traveller standing there is on.
    private func tafTimeline(_ periods: [TafPeriod], zone: TimeZone?) -> some View {
        InsetSurface {
            timelineContent(periods, zone: zone)
        }
    }

    private func timelineContent(_ periods: [TafPeriod], zone: TimeZone?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Forecast periods")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                if let city = AirportTimeZones.cityName(zone) {
                    Text("· \(city) time")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            ForEach(Array(periods.prefix(5).enumerated()), id: \.offset) { _, period in
                HStack(spacing: 8) {
                    Text(TimeFmt.clock(period.timeFrom, zone: zone))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 64, alignment: .leading)
                    if let change = FAAGlossary.decodeChangeIndicator(period.changeIndicator) {
                        Text(change)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.teal)
                    }
                    Text(periodSummary(period))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
    }

    private func periodSummary(_ period: TafPeriod) -> String {
        var parts: [String] = []
        if let wind = period.wind?.summary { parts.append(wind) }
        if let vis = period.visibilitySm { parts.append("\(vis) sm") }
        if let ceiling = period.ceilingFt { parts.append("ceiling \(Int(ceiling)) ft") }
        if let weather = period.weather { parts.append(weather) }
        return parts.isEmpty ? "No change details" : parts.joined(separator: " · ")
    }

    // MARK: - Lookup

    private func lookup(_ raw: String) {
        let icao = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard icao.count >= 3, icao.count <= 4 else {
            errorMessage = "Enter a 3-4 letter ICAO code, like KJFK."
            return
        }
        Haptics.tap()
        searchFocused = false
        isLoading = true
        errorMessage = nil
        lookedUpIcao = nil
        lastAttempted = icao

        Task {
            async let metarTask = try? API.metar(icaos: [icao])
            async let tafTask = try? API.taf(icaos: [icao])
            async let faaTask = try? API.faaStatus(icaos: [icao])
            async let lightningTask = try? API.lightning(icao: icao)

            let (metarEnv, tafEnv, faaEnv, lightningEnv) =
                await (metarTask, tafTask, faaTask, lightningTask)

            metar = metarEnv?.data?[icao]
            taf = tafEnv?.data?[icao]
            faa = faaEnv?.data?[icao]
            lightning = lightningEnv

            if metar == nil && taf == nil && faa == nil {
                errorMessage = "Nothing came back for \(icao). Double-check the code — US airports usually start with K."
            } else {
                lookedUpIcao = icao
                var updated = recents.filter { $0 != icao }
                updated.insert(icao, at: 0)
                recents = Array(updated.prefix(8))
                UserDefaults.standard.set(recents, forKey: "pft.recentAirports")
            }
            isLoading = false
        }
    }
}
