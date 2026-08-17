import SwiftUI

// MARK: - Popup routing

/// Everything that can appear in a floating detail card.
enum DetailPopup: Identifiable {
    case riskSignal(RiskSignal)
    case weather(icao: String, metar: MetarObservation?, taf: TafReport?, faa: FaaAirportStatus?)
    case faaPrograms(icao: String, record: FaaAirportStatus)
    case jargon(GlossaryEntry)

    var id: String {
        switch self {
        case .riskSignal(let signal): return "risk-\(signal.key)"
        case .weather(let icao, _, _, _): return "wx-\(icao)"
        case .faaPrograms(let icao, _): return "faa-\(icao)"
        case .jargon(let entry): return "gloss-\(entry.term)"
        }
    }

    var title: String {
        switch self {
        case .riskSignal(let signal): return signal.title
        case .weather(let icao, _, _, _): return "Weather — \(icao)"
        case .faaPrograms(let icao, _): return "FAA programs — \(icao)"
        case .jargon(let entry): return entry.term
        }
    }

    var icon: String {
        switch self {
        case .riskSignal(let signal): return signal.icon
        case .weather: return "cloud-sun"
        case .faaPrograms: return "octagon-alert"
        case .jargon: return "book-open"
        }
    }

    var tint: Color {
        switch self {
        case .riskSignal(let signal): return signal.level.color
        case .weather: return Theme.teal
        case .faaPrograms(_, let record):
            return (record.groundStops ?? []).isEmpty ? Theme.gold : Theme.red
        case .jargon: return Theme.teal
        }
    }
}

/// Hosts a popup inside the floating card cover.
struct DetailPopupHost: View {
    let popup: DetailPopup

    var body: some View {
        FloatingCardCover(title: popup.title, icon: popup.icon, tint: popup.tint) {
            DetailPopupBody(popup: popup)
        }
    }
}

/// Popup content with an inline jargon-definition bubble so tapping a dotted
/// term keeps the current card open.
struct DetailPopupBody: View {
    let popup: DetailPopup

    @State private var jargon: GlossaryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch popup {
            case .riskSignal(let signal):
                RiskSignalPopupContent(signal: signal)
            case .weather(let icao, let metar, let taf, let faa):
                WeatherPopupContent(icao: icao, metar: metar, taf: taf, faa: faa)
            case .faaPrograms(let icao, let record):
                FaaProgramsPopupContent(icao: icao, record: record)
            case .jargon(let entry):
                JargonPopupContent(entry: entry)
            }

            if let jargon {
                JargonBubble(entry: jargon) {
                    withAnimation(.snappy) { self.jargon = nil }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .glossaryLinkHandler { entry in
            Haptics.tap()
            withAnimation(.snappy) { jargon = entry }
        }
    }
}

// MARK: - Glossary text plumbing

/// Text with known FAA abbreviations rendered as tappable dotted-underline links.
struct GlossaryText: View {
    let text: String
    var font: Font = .caption
    var color: Color = Theme.inkSecondary

    var body: some View {
        Text(FAAGlossary.attributed(text))
            .font(font)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// Intercepts glossary:// links from `GlossaryText` and routes them
    /// to a definition handler instead of the system browser.
    func glossaryLinkHandler(_ open: @escaping (GlossaryEntry) -> Void) -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "glossary" else { return .systemAction }
            let raw = url.lastPathComponent
            let term = raw.removingPercentEncoding ?? raw
            if let entry = FAAGlossary.entry(for: term) {
                open(entry)
                return .handled
            }
            return .discarded
        })
    }
}

/// Compact inline definition bubble shown inside popups.
struct JargonBubble: View {
    let entry: GlossaryEntry
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LucideIcon(name: "book-open", size: 12, fallback: "book")
                    .foregroundStyle(Theme.teal)
                Text("\(entry.term) — \(entry.name)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onClose) {
                    LucideIcon(name: "x", size: 11, fallback: "xmark")
                        .foregroundStyle(Theme.inkSecondary)
                }
                .accessibilityLabel("Close definition")
            }
            Text(entry.definition)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.teal.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.teal.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Risk signal popup

struct RiskSignalPopupContent: View {
    let signal: RiskSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RiskBadge(level: signal.level)

            popupBlock(title: "Why this fired") {
                GlossaryText(text: signal.detail, font: .subheadline)
            }

            if let explanation = FAAGlossary.explain(signalKey: signal.key) {
                popupBlock(title: "What it means") {
                    GlossaryText(text: explanation.meaning, font: .subheadline)
                }
                popupBlock(title: "What usually happens next") {
                    GlossaryText(text: explanation.next, font: .subheadline)
                }
            }
        }
    }
}

// MARK: - Weather popup

struct WeatherPopupContent: View {
    let icao: String
    let metar: MetarObservation?
    let taf: TafReport?
    let faa: FaaAirportStatus?

    /// Observation and forecast times read in this airport's local time.
    private var zone: TimeZone? { AirportTimeZones.zone(for: icao) }
    private var zoneCity: String? { AirportTimeZones.cityName(zone) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let category = metar?.flightCategory {
                categoryBlock(category)
            }

            if let metar {
                popupBlock(title: "Current observation") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let time = metar.observationTime {
                            row("Observed", TimeFmt.clock(time, zone: zone),
                                note: [zoneCity.map { "\($0) local time." }, relativeNote(time)]
                                    .compactMap { $0 }.joined(separator: " "))
                        }
                        if let wind = metar.wind?.summary {
                            row("Wind", wind, note: gustNote(metar.wind))
                        }
                        if let vis = metar.visibilitySm {
                            row("Visibility", "\(vis) statute miles")
                        }
                        if let ceiling = metar.ceilingFt {
                            row("Ceiling", "\(Int(ceiling)) ft",
                                note: "The lowest broken or overcast cloud layer.")
                        }
                        if let clouds = metar.clouds, !clouds.isEmpty {
                            cloudRows(clouds)
                        }
                        if let temp = metar.temperatureC {
                            row("Temperature", temperatureText(temp, metar.dewpointC),
                                note: spreadNote(temp, metar.dewpointC))
                        }
                        if let altimeter = metar.altimeterMb {
                            row("Pressure", "\(Int(altimeter)) mb")
                        }
                        if let wx = metar.weatherPhenomena, !wx.isEmpty {
                            row("Active weather", FAAGlossary.decodeWx(wx))
                        }
                    }
                }
            } else {
                Text("No current observation available for \(icao).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }

            if let faa {
                faaBlock(faa)
            }

            if let taf {
                forecastBlock(taf)
            }

            rawBlock
        }
    }

    private func categoryBlock(_ category: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(categoryColor(category))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(categoryColor(category).opacity(0.13))
                .clipShape(.capsule)
            GlossaryText(text: FAAGlossary.categoryExplanation(category), font: .subheadline)
        }
    }

    private func faaBlock(_ record: FaaAirportStatus) -> some View {
        popupBlock(title: "FAA traffic programs") {
            if record.hasAnyProgram {
                VStack(alignment: .leading, spacing: 6) {
                    if !(record.groundStops ?? []).isEmpty {
                        GlossaryText(text: "Ground stop active — departures to \(icao) are held on the ground at their origin. GS is the FAA's strictest measure.", font: .subheadline)
                    }
                    if !(record.groundDelayPrograms ?? []).isEmpty {
                        let note = record.gdpDelaySummary.map { " Current \($0.replacingOccurrences(of: "avg", with: "average delay is"))." } ?? ""
                        GlossaryText(text: "GDP active — arrivals are metered and departing flights receive EDCT wheels-up slots.\(note)", font: .subheadline)
                    }
                    if !(record.arrivalDepartureDelays ?? []).isEmpty {
                        let range = record.delayRangeText.map { " Currently \($0)" + (record.delayTrend == "increasing" ? " and climbing." : record.delayTrend == "decreasing" ? " and easing." : ".") } ?? ""
                        GlossaryText(text: "General arrival/departure delays reported on the NAS status board.\(range)", font: .subheadline)
                    }
                    if !(record.closures ?? []).isEmpty {
                        GlossaryText(text: "A runway or airport closure is in effect, reducing hourly capacity.", font: .subheadline)
                    }
                    Text("Tap a program chip on the weather card for the full FAA details.")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
            } else {
                HStack(spacing: 6) {
                    LucideIcon(name: "circle-check", size: 13, fallback: "checkmark.circle")
                    Text("No active FAA programs at \(icao).")
                        .font(.subheadline)
                }
                .foregroundStyle(Theme.green)
            }
        }
    }

    private func forecastBlock(_ taf: TafReport) -> some View {
        popupBlock(title: "Forecast (TAF)") {
            VStack(alignment: .leading, spacing: 8) {
                if let from = taf.validFrom, let to = taf.validTo {
                    Text("Valid \(TimeFmt.clock(from, zone: zone)) → \(TimeFmt.clock(to, zone: zone))"
                         + (zoneCity.map { " · \($0) time" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
                ForEach(Array((taf.forecastPeriods ?? []).prefix(8).enumerated()), id: \.offset) { _, period in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(TimeFmt.clock(period.timeFrom, zone: zone))
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            if let change = FAAGlossary.decodeChangeIndicator(period.changeIndicator) {
                                Text(change)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Theme.teal)
                            }
                        }
                        Text(periodSummary(period))
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rawBlock: some View {
        if metar?.raw != nil || taf?.raw != nil {
            popupBlock(title: "Raw reports") {
                VStack(alignment: .leading, spacing: 6) {
                    if let raw = metar?.raw {
                        Text(raw)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.inkSecondary)
                            .textSelection(.enabled)
                    }
                    if let rawTaf = taf?.raw {
                        Text(rawTaf)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.inkSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    // MARK: helpers

    private func cloudRows(_ clouds: [CloudLayer]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cloud layers")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
            ForEach(Array(clouds.prefix(5).enumerated()), id: \.offset) { _, layer in
                HStack(spacing: 6) {
                    if let base = layer.baseAglFt {
                        Text("\(Int(base)) ft")
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.ink)
                    }
                    Text(FAAGlossary.cloudCoverage(layer.coverage ?? ""))
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private func periodSummary(_ period: TafPeriod) -> String {
        var parts: [String] = []
        if let wind = period.wind?.summary { parts.append("Wind \(wind)") }
        if let vis = period.visibilitySm { parts.append("\(vis) sm visibility") }
        if let ceiling = period.ceilingFt { parts.append("ceiling \(Int(ceiling)) ft") }
        if let weather = period.weather, !weather.isEmpty {
            parts.append(FAAGlossary.decodeWx(weather))
        }
        return parts.isEmpty ? "No significant change" : parts.joined(separator: " · ")
    }

    private func temperatureText(_ temp: Double, _ dewpoint: Double?) -> String {
        if let dewpoint {
            return "\(Int(temp))°C (dewpoint \(Int(dewpoint))°C)"
        }
        return "\(Int(temp))°C"
    }

    private func spreadNote(_ temp: Double, _ dewpoint: Double?) -> String? {
        guard let dewpoint, temp - dewpoint <= 2 else { return nil }
        return "Temperature and dewpoint are close — fog or low clouds can form."
    }

    private func gustNote(_ wind: WindInfo?) -> String? {
        guard let gust = wind?.gustKts, gust >= 25 else { return nil }
        return "Gusts this strong force wider spacing between arrivals."
    }

    private func relativeNote(_ iso: String) -> String? {
        guard let date = TimeFmt.parseISO(iso) else { return nil }
        return "Reported \(TimeFmt.relative(date))."
    }

    private func row(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 88, alignment: .leading)
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.leading, 96)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

// MARK: - FAA programs popup

struct FaaProgramsPopupContent: View {
    let icao: String
    let record: FaaAirportStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            programSection(
                title: "Ground stop",
                color: Theme.red,
                icon: "octagon-alert",
                explanation: "Flights bound for \(icao) are held on the ground at their departure airports until the stop is lifted — the FAA's strictest traffic measure. Stops usually have a published end time but often extend.",
                items: record.groundStops)

            programSection(
                title: "Ground delay program",
                color: Theme.gold,
                icon: "timer",
                explanation: "The FAA is metering arrivals into \(icao). Departing flights get an EDCT — a fixed wheels-up slot — so boarding can finish on time and the aircraft still waits.",
                items: record.groundDelayPrograms)

            programSection(
                title: "Arrival / departure delays",
                color: Theme.gold,
                icon: "hourglass",
                explanation: "The NAS status board is reporting general delays at \(icao) — volume, weather, staffing, or runway configuration.",
                items: record.arrivalDepartureDelays)

            programSection(
                title: "Closures",
                color: Theme.gold,
                icon: "construction",
                explanation: "A runway or portion of \(icao) is closed, cutting the airport's hourly capacity.",
                items: record.closures)

            if !record.hasAnyProgram {
                HStack(spacing: 6) {
                    LucideIcon(name: "circle-check", size: 13, fallback: "checkmark.circle")
                    Text("No active FAA programs at \(icao) right now.")
                        .font(.subheadline)
                }
                .foregroundStyle(Theme.green)
            }
        }
    }

    @ViewBuilder
    private func programSection(title: String, color: Color, icon: String,
                                explanation: String, items: [JSONValue]?) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    LucideIcon(name: icon, size: 13, fallback: "exclamationmark.triangle")
                        .foregroundStyle(color)
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                    Spacer()
                }
                GlossaryText(text: explanation, font: .subheadline)
                ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                    programDetails(item)
                }
            }
            .padding(12)
            .background(color.opacity(0.07))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func programDetails(_ item: JSONValue) -> some View {
        if let object = item.objectValue {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(detailPairs(object), id: \.0) { pair in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(pair.0)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Text(pair.1)
                            .font(.caption)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(.rect(cornerRadius: 10))
        } else if let text = item.stringValue {
            GlossaryText(text: text, font: .caption, color: Theme.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(.rect(cornerRadius: 10))
        }
    }

    private func detailPairs(_ object: [String: JSONValue]) -> [(String, String)] {
        object.sorted { $0.key < $1.key }.compactMap { key, value in
            guard let text = value.stringValue, !text.isEmpty else { return nil }
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            return (label, text)
        }
    }
}

// MARK: - Jargon popup

struct JargonPopupContent: View {
    let entry: GlossaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            GlossaryText(text: entry.definition, font: .subheadline)
        }
    }
}

// MARK: - Shared block helper

@ViewBuilder
func popupBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.ink)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.canvas)
    .clipShape(.rect(cornerRadius: 12))
}
