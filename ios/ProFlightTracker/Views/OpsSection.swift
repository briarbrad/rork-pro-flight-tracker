import SwiftUI

/// Aviation-nerd deep dive: NOTAMs, RVR, lightning, PIREPs, SIGMETs.
/// Loaded on demand — and horizon-gated: these feeds only describe the next
/// few hours, so beyond the same-day window the section locks instead of
/// pulling data that can't inform the flight (and that /api/brief skipped).
struct OpsSection: View {
    let originIcao: String?
    let destIcao: String?
    var hoursToDeparture: Double? = nil
    /// True inside the evidence drawer — drops the card shell so the drawer
    /// and this section read as one surface. Lazy loading is unchanged:
    /// feeds still only fire when the user expands the deep-dive.
    var embedded: Bool = false

    @State private var isExpanded: Bool = false
    @State private var isLoading: Bool = false
    @State private var notams: SwimEnvelope?
    @State private var rvr: JSONValue?
    @State private var lightning: LightningEnvelope?
    @State private var pireps: JSONValue?
    @State private var itws: SwimEnvelope?
    @State private var loadError: String?
    @State private var showRawNotams: Bool = false
    @State private var showRawPireps: Bool = false

    var body: some View {
        if originIcao != nil || destIcao != nil {
            if HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: hoursToDeparture) {
                if embedded { liveCard } else { liveCard.cardStyle() }
            } else {
                if embedded { lockedCard } else { lockedCard.cardStyle() }
            }
        }
    }

    private var liveCard: some View {
            VStack(alignment: .leading, spacing: Space.sm) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { isExpanded.toggle() }
                    if isExpanded, notams == nil, !isLoading {
                        loadOps()
                    }
                } label: {
                    HStack(spacing: 8) {
                        LucideIcon(name: "telescope", size: 16, fallback: "binoculars")
                            .foregroundStyle(Theme.teal)
                        Text("Ops deep-dive")
                            .font(TypeScale.sectionTitle)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if isLoading {
                            ProgressView().controlSize(.small).tint(Theme.teal)
                        }
                        LucideIcon(name: isExpanded ? "chevron-up" : "chevron-down",
                                   size: 15, fallback: "chevron.down")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    if let loadError {
                        InlineNotice(style: .error,
                                     message: loadError,
                                     actionLabel: "Retry",
                                     actionDisabled: isLoading) {
                            loadOps()
                        }
                    }
                    if isLoading && notams == nil {
                        Text("Pulling NOTAMs, RVR, lightning, ITWS, and pilot reports — live FAA feeds take a few seconds…")
                            .font(TypeScale.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    lightningBlock
                    itwsBlock
                    rvrBlock
                    notamBlock
                    pirepBlock
                }
            }
    }

    /// Shown while departure is beyond the same-day window. No fetches fire.
    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LucideIcon(name: "telescope", size: 16, fallback: "binoculars")
                    .foregroundStyle(Theme.inkSecondary)
                Text("Ops deep-dive")
                    .font(TypeScale.sectionTitle)
                    .foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 4) {
                    LucideIcon(name: "lock", size: 11, fallback: "lock")
                    Text(unlockText)
                        .font(TypeScale.caption2Strong)
                }
                .foregroundStyle(Theme.inkSecondary)
            }
            Text("Lightning, runway visual range, NOTAMs, ITWS terminal weather, and pilot reports describe the next few hours — this far out they can't tell you anything about your departure, so the app doesn't pull them yet.")
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unlockText: String {
        guard let hours = hoursToDeparture, hours > HorizonGate.sameDayWindowHours else {
            return "Unlocks closer to departure"
        }
        let remaining = Int((hours - HorizonGate.sameDayWindowHours).rounded())
        return remaining <= 1 ? "Unlocks within the hour" : "Unlocks in ~\(remaining)h"
    }

    // MARK: - Loading

    private func loadOps() {
        guard let airport = destIcao ?? originIcao else { return }
        let origin = originIcao ?? airport
        isLoading = true
        loadError = nil
        Task {
            async let notamTask = try? API.notams(airportIcao: airport)
            async let rvrTask = try? API.rvr(airportIcao: origin)
            async let lightningTask = try? API.lightning(icao: origin)
            async let pirepTask = try? API.pireps(icao: airport)
            async let itwsTask = try? API.itws(airportIcao: origin)

            let (notamResult, rvrResult, lightningResult, pirepResult, itwsResult) =
                await (notamTask, rvrTask, lightningTask, pirepTask, itwsTask)

            notams = notamResult
            rvr = rvrResult
            lightning = lightningResult
            pireps = pirepResult
            itws = itwsResult
            if notamResult == nil && rvrResult == nil && lightningResult == nil
                && pirepResult == nil && itwsResult == nil {
                loadError = "Couldn't reach the ops feeds. Try again in a moment."
            }
            isLoading = false
        }
    }

    // MARK: - Blocks

    @ViewBuilder
    private var lightningBlock: some View {
        if let lightning {
            opsBlock(icon: "zap", title: "Lightning — \(lightning.airport ?? "")") {
                if let error = lightning.error {
                    Text(error).font(TypeScale.caption).foregroundStyle(Theme.inkSecondary)
                } else {
                    let close = lightning.strikesWithin5nm ?? 0
                    let total = lightning.totalStrikes ?? 0
                    Text(total == 0
                         ? "No strikes detected within \(Int(lightning.searchRadiusNm ?? 20)) nm."
                         : "\(total) strikes in the area, \(close) within 5 nm. Ramp closure risk: \(lightning.rampClosureRisk ?? "unknown").")
                        .font(TypeScale.caption)
                        .foregroundStyle(close > 0 ? Theme.goldText : Theme.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var itwsBlock: some View {
        if let itws {
            opsBlock(icon: "radar", title: "ITWS terminal weather — \(originIcao ?? destIcao ?? "")") {
                if let error = itws.error {
                    Text(error).font(TypeScale.caption).foregroundStyle(Theme.inkSecondary)
                } else {
                    let alerts = ItwsAlert.parse(from: itws)
                    if alerts.isEmpty {
                        Text(itws.isQuiet
                             ? "Feed was quiet during the capture window — no microburst, gust-front, or wind-shear alerts."
                             : "No microburst, gust-front, or wind-shear alerts at this airport.")
                            .font(TypeScale.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    } else {
                        ForEach(Array(alerts.prefix(4).enumerated()), id: \.offset) { _, alert in
                            HStack(alignment: .top, spacing: 6) {
                                LucideIcon(name: itwsIcon(alert.kindCode), size: 12,
                                           fallback: "exclamationmark.triangle")
                                    .foregroundStyle(itwsTone(alert.kindCode).color)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.headline)
                                        .font(TypeScale.captionStrong)
                                        .foregroundStyle(Theme.ink)
                                    if let detail = alert.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(TypeScale.caption2)
                                            .foregroundStyle(Theme.inkSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }

    private func itwsIcon(_ kind: String) -> String {
        switch kind {
        case "MICROBURST": return "octagon-alert"
        case "GUST_FRONT": return "wind"
        case "WIND_SHEAR": return "waves"
        default: return "cloud-lightning"
        }
    }

    private func itwsTone(_ kind: String) -> ChipTone {
        switch kind {
        case "MICROBURST": return .alert
        case "GUST_FRONT", "WIND_SHEAR": return .watch
        default: return .info
        }
    }

    @ViewBuilder
    private var rvrBlock: some View {
        if let rvr {
            opsBlock(icon: "eye", title: "Runway visual range") {
                if let runways = rvr["runways"]?.arrayValue, !runways.isEmpty {
                    ForEach(Array(runways.prefix(6).enumerated()), id: \.offset) { _, runway in
                        HStack {
                            Text("Rwy \(runway["runway"]?.stringValue ?? "?")")
                                .font(TypeScale.captionStrong)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(rvrText(runway))
                                .font(TypeScale.mono)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    if let risk = rvr["visibility_risk"]?.stringValue {
                        Text("Visibility risk: \(risk)")
                            .font(TypeScale.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else if let error = rvr["error"]?.stringValue {
                    Text(error).font(TypeScale.caption).foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("No RVR sensor data for this airport.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private func rvrText(_ runway: JSONValue) -> String {
        for key in ["touchdown_ft", "rvr_ft", "touchdown", "visual_range_ft", "value"] {
            if let value = runway[key]?.stringValue { return "\(value) ft" }
        }
        return runway["status"]?.stringValue ?? "—"
    }

    @ViewBuilder
    private var notamBlock: some View {
        if let notams {
            opsBlock(icon: "file-warning", title: "NOTAMs — \(destIcao ?? originIcao ?? "")") {
                if let error = notams.error {
                    Text(error).font(TypeScale.caption).foregroundStyle(Theme.inkSecondary)
                } else if let results = notams.results, !results.isEmpty {
                    rawToggle(isRaw: $showRawNotams)
                    ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { _, notam in
                        if showRawNotams {
                            Text(notamText(notam))
                                .font(TypeScale.mono)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(4)
                                .padding(.vertical, 2)
                        } else {
                            GlossaryText(text: FAAGlossary.expandNotam(notamText(notam)))
                                .lineLimit(6)
                                .padding(.vertical, 2)
                        }
                    }
                    if results.count > 5 {
                        Text("+ \(results.count - 5) more")
                            .font(TypeScale.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                } else if notams.isQuiet {
                    Text("Feed was quiet during the capture window — no new NOTAMs broadcast.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("No NOTAMs matched this airport.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private func notamText(_ notam: JSONValue) -> String {
        for key in ["text", "notam_text", "message", "raw", "description"] {
            if let value = notam[key]?.stringValue, !value.isEmpty { return value }
        }
        if let object = notam.objectValue {
            let pairs = object.compactMap { key, value -> String? in
                guard let text = value.stringValue, !text.isEmpty else { return nil }
                return "\(key): \(text)"
            }
            return pairs.prefix(3).joined(separator: " · ")
        }
        return "NOTAM entry"
    }

    @ViewBuilder
    private var pirepBlock: some View {
        if let pireps {
            opsBlock(icon: "message-circle", title: "Pilot reports") {
                if let reports = pireps["data"]?.arrayValue, !reports.isEmpty {
                    rawToggle(isRaw: $showRawPireps)
                    ForEach(Array(reports.prefix(4).enumerated()), id: \.offset) { _, report in
                        if showRawPireps {
                            Text(pirepText(report))
                                .font(TypeScale.mono)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(3)
                                .padding(.vertical, 2)
                        } else {
                            GlossaryText(text: FAAGlossary.decodePirep(pirepText(report)))
                                .padding(.vertical, 2)
                        }
                    }
                } else {
                    Text("No recent PIREPs near this airport.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private func pirepText(_ report: JSONValue) -> String {
        for key in ["raw", "raw_text", "report", "text"] {
            if let value = report[key]?.stringValue, !value.isEmpty { return value }
        }
        return "PIREP entry"
    }

    /// Small trailing toggle between plain-English and raw source text.
    private func rawToggle(isRaw: Binding<Bool>) -> some View {
        HStack {
            Spacer()
            Button {
                Haptics.tap()
                withAnimation(.snappy) { isRaw.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 4) {
                    LucideIcon(name: isRaw.wrappedValue ? "languages" : "file-code",
                               size: 10, fallback: "doc.plaintext")
                    Text(isRaw.wrappedValue ? "Plain English" : "Raw")
                        .font(TypeScale.caption2Strong)
                }
                .foregroundStyle(Theme.teal)
            }
        }
    }

    private func opsBlock<Content: View>(icon: String, title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        InsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    LucideIcon(name: icon, size: 13, fallback: "circle")
                        .foregroundStyle(Theme.teal)
                    Text(title)
                        .font(TypeScale.captionBold)
                        .foregroundStyle(Theme.ink)
                }
                content()
            }
        }
    }
}
