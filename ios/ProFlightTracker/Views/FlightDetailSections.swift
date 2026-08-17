import SwiftUI
import MapKit

// MARK: - Live signals

/// One fired signal row — severity icon, title, reason, optional info tap.
struct SignalRow: View {
    let signal: RiskSignal
    var onSelect: ((RiskSignal) -> Void)? = nil

    var body: some View {
        Button {
            onSelect?(signal)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(signal.level.color.opacity(0.14))
                        .frame(width: 32, height: 32)
                    LucideIcon(name: signal.icon, size: 15, fallback: "exclamationmark")
                        .foregroundStyle(signal.level.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(signal.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if onSelect != nil {
                    LucideIcon(name: "info", size: 14, fallback: "info.circle")
                        .foregroundStyle(Theme.teal)
                        .padding(.top, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
    }
}

/// Flat list of fired live signals. Deliberately NOT a verdict — the
/// flight-level verdict comes exclusively from the pre-flight brief. Hidden
/// when empty unless an explicit empty text is provided, so the app never
/// declares "all clean" on the signal engine's authority.
struct SignalListSection: View {
    let title: String
    let icon: String
    var caption: String? = nil
    let signals: [RiskSignal]
    var emptyText: String? = nil
    var onSelect: ((RiskSignal) -> Void)? = nil

    var body: some View {
        if !signals.isEmpty || emptyText != nil {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: icon, title: title)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if signals.isEmpty {
                    if let emptyText {
                        Text(emptyText)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else {
                    ForEach(signals) { signal in
                        SignalRow(signal: signal, onSelect: onSelect)
                    }
                }
            }
            .cardStyle()
        }
    }
}

// MARK: - Inbound aircraft chain

/// Where your actual airplane is: inbound leg, tail, and turn-time analysis.
struct ChainSection: View {
    let chain: ChainData
    /// Zone of the airport the inbound leg lands at — i.e. this flight's origin.
    var arrivalZone: TimeZone? = nil
    var onOpenInbound: ((AeroFlight) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "link", title: "Your aircraft")

            HStack(spacing: 12) {
                if let tail = chain.tailNumber {
                    chip(icon: "plane", text: tail)
                }
                if let type = chain.aircraftType {
                    chip(icon: "info", text: type)
                }
                if let category = chain.aircraftCategory {
                    chip(icon: "ruler", text: category.capitalized)
                }
                Spacer()
            }

            if let inbound = chain.inboundFlight {
                Button {
                    onOpenInbound?(inbound)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Inbound leg — \(inbound.ident ?? "unknown")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary)
                            Spacer()
                            if onOpenInbound != nil {
                                HStack(spacing: 3) {
                                    Text("View flight")
                                        .font(.caption2.weight(.semibold))
                                    LucideIcon(name: "chevron-right", size: 11, fallback: "chevron.right")
                                }
                                .foregroundStyle(Theme.teal)
                            }
                        }
                        HStack {
                            Text(inbound.originDisplay)
                                .font(.headline.weight(.bold))
                            LucideIcon(name: "move-right", size: 14, fallback: "arrow.right")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(inbound.destDisplay)
                                .font(.headline.weight(.bold))
                            Spacer()
                            Text(inboundArrivalText(inbound))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(inboundLate ? Theme.gold : Theme.inkSecondary)
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    .padding(12)
                    .background(Theme.canvas)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(onOpenInbound == nil)
            } else {
                Text("No inbound leg data — the aircraft may originate here.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }

            if let turn = chain.turnAnalysis {
                turnRow(turn)
            }
        }
        .cardStyle()
    }

    /// Inbound arrival in the local time of the airport it lands at.
    private func inboundArrivalText(_ inbound: AeroFlight) -> String {
        let zone = arrivalZone
            ?? AirportTimeZones.zone(forAnyOf: inbound.destIcao, inbound.destIata)
        if let actual = inbound.actualIn {
            return "Arrived \(TimeFmt.clock(actual, zone: zone))"
        }
        return "ETA \(TimeFmt.clock(inbound.estimatedIn ?? inbound.scheduledIn, zone: zone))"
    }

    private var inboundLate: Bool {
        guard let inbound = chain.inboundFlight else { return false }
        let slip = TimeFmt.slipMinutes(scheduled: inbound.scheduledIn,
                                       actual: inbound.actualIn,
                                       estimated: inbound.estimatedIn) ?? 0
        return slip >= 20 && inbound.actualIn == nil
    }

    private func turnRow(_ turn: TurnAnalysis) -> some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(name: "timer", size: 16, fallback: "timer")
                .foregroundStyle(turnColor(turn))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                if let minutes = turn.turnTimeAvailableMin {
                    Text("Turn time: \(Int(minutes)) min available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                if let note = turn.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func turnColor(_ turn: TurnAnalysis) -> Color {
        if let minutes = turn.turnTimeAvailableMin, minutes < 0 { return Theme.red }
        if turn.sufficient == false { return Theme.gold }
        return Theme.green
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
}

// MARK: - Map preview

/// Small embedded map when a live position exists; taps expand full-screen.
struct MapPreviewSection: View {
    let position: AircraftPosition?
    let flightIdent: String
    let onExpand: () -> Void

    var body: some View {
        if let position, let lat = position.latitude, let lon = position.longitude {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "map", title: "Live position")

                Button(action: onExpand) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)))) {
                        Annotation(flightIdent, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                            PlaneMarker(heading: position.heading ?? 0)
                        }
                    }
                    .frame(height: 170)
                    .clipShape(.rect(cornerRadius: 14))
                    .allowsHitTesting(false)
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 4) {
                            LucideIcon(name: "expand", size: 11, fallback: "arrow.up.left.and.arrow.down.right")
                            Text("Expand")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55))
                        .clipShape(.capsule)
                        .padding(8)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    if let alt = position.altitudeFt {
                        statChip(icon: "mountain", text: "\(Int(alt)) ft")
                    }
                    if let speed = position.groundspeedKts {
                        statChip(icon: "gauge", text: "\(Int(speed)) kt")
                    }
                    if let source = position.source {
                        statChip(icon: "radio", text: source.replacingOccurrences(of: "_", with: " "))
                    }
                    Spacer()
                }
            }
            .cardStyle()
        }
    }

    private func statChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            LucideIcon(name: icon, size: 11, fallback: "circle")
            Text(text)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(Theme.teal)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.teal.opacity(0.1))
        .clipShape(.capsule)
    }
}

/// Rotated plane glyph used as a map annotation.
struct PlaneMarker: View {
    let heading: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.teal)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            Image(systemName: "airplane")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(heading - 90))
        }
    }
}

// MARK: - Airport weather

/// METAR/TAF + FAA program chips for origin and destination. This is a
/// CURRENT-CONDITIONS reference display, never a flight assessment — the
/// flight-level meaning of any condition comes from the brief's effects[].
struct WeatherSection: View {
    let leg: AeroFlight?
    let metar: [String: MetarObservation]?
    let taf: [String: TafReport]?
    let faa: [String: FaaAirportStatus]?
    var title: String = "Airport weather & FAA status"
    var horizonNote: String? = nil
    var onOpenWeather: ((String) -> Void)? = nil
    var onOpenFaa: ((String) -> Void)? = nil

    var body: some View {
        let airports = airportList
        if !airports.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "cloud-sun", title: title)
                if let horizonNote {
                    HStack(alignment: .top, spacing: 6) {
                        LucideIcon(name: "hourglass", size: 12, fallback: "hourglass")
                            .padding(.top, 1)
                        Text(horizonNote)
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                }
                ForEach(airports, id: \.self) { icao in
                    AirportWeatherCard(icao: icao,
                                       metar: metar?[icao],
                                       taf: taf?[icao],
                                       faa: faa?[icao],
                                       onOpenWeather: onOpenWeather.map { open in { open(icao) } },
                                       onOpenFaa: onOpenFaa.map { open in { open(icao) } })
                }
            }
            .cardStyle()
        }
    }

    private var airportList: [String] {
        var list: [String] = []
        if let origin = leg?.originIcao { list.append(origin) }
        if let dest = leg?.destIcao, !list.contains(dest) { list.append(dest) }
        return list
    }
}

/// One airport's decoded conditions, raw METAR, and FAA program chips.
struct AirportWeatherCard: View {
    let icao: String
    let metar: MetarObservation?
    let taf: TafReport?
    let faa: FaaAirportStatus?
    var onOpenWeather: (() -> Void)? = nil
    var onOpenFaa: (() -> Void)? = nil

    @State private var showRaw: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onOpenWeather?()
                } label: {
                    HStack(spacing: 8) {
                        Text(icao)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        if let category = metar?.flightCategory {
                            Text(category)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(categoryColor(category))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(categoryColor(category).opacity(0.13))
                                .clipShape(.capsule)
                        }
                        if onOpenWeather != nil {
                            LucideIcon(name: "info", size: 13, fallback: "info.circle")
                                .foregroundStyle(Theme.teal)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(onOpenWeather == nil)
                Spacer()
                if metar?.raw != nil || taf?.raw != nil {
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy) { showRaw.toggle() }
                    } label: {
                        Text(showRaw ? "Decoded" : "Raw")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.teal)
                    }
                }
            }

            if let faa {
                faaChips(faa)
            }

            if showRaw {
                VStack(alignment: .leading, spacing: 6) {
                    if let raw = metar?.raw {
                        Text(raw)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.ink)
                    }
                    if let rawTaf = taf?.raw {
                        Text(rawTaf)
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            } else if let metar {
                Button {
                    onOpenWeather?()
                } label: {
                    Text(metar.decoded)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(onOpenWeather == nil)
            } else {
                Text("No observation available.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(12)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func faaChips(_ record: FaaAirportStatus) -> some View {
        if record.hasAnyProgram {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if !(record.groundStops ?? []).isEmpty {
                        programChip("Ground stop", color: Theme.red, icon: "octagon-alert")
                    }
                    if !(record.groundDelayPrograms ?? []).isEmpty {
                        programChip(record.gdpDelaySummary.map { "GDP \($0)" } ?? "GDP",
                                    color: Theme.gold, icon: "timer")
                    }
                    if !(record.arrivalDepartureDelays ?? []).isEmpty {
                        programChip(record.delayChipText.map { "Delays \($0)" } ?? "Delays",
                                    color: Theme.gold, icon: "hourglass")
                    }
                    if !(record.closures ?? []).isEmpty {
                        programChip("Closure", color: Theme.gold, icon: "construction")
                    }
                }
            }
        } else {
            HStack(spacing: 4) {
                LucideIcon(name: "circle-check", size: 11, fallback: "checkmark.circle")
                Text("No active FAA programs")
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(Theme.green)
        }
    }

    private func programChip(_ text: String, color: Color, icon: String) -> some View {
        Button {
            onOpenFaa?()
        } label: {
            HStack(spacing: 4) {
                LucideIcon(name: icon, size: 11, fallback: "exclamationmark.triangle")
                Text(text)
                    .font(.caption2.weight(.bold))
                if onOpenFaa != nil {
                    LucideIcon(name: "chevron-right", size: 9, fallback: "chevron.right")
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.13))
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(onOpenFaa == nil)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.uppercased() {
        case "VFR": return Theme.green
        case "MVFR": return Theme.teal
        case "IFR": return Theme.gold
        case "LIFR": return Theme.red
        default: return Theme.inkSecondary
        }
    }
}
