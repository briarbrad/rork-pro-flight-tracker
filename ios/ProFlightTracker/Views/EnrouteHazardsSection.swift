import SwiftUI

/// Convective forecast + international SIGMETs for the route. Both are
/// reference layers: the FAA's TCF is the product traffic management reads
/// before calling a thunderstorm ground stop, and international SIGMETs fill
/// the gap where the CONUS feed stops. Neither moves the verdict — the brief
/// stays the single flight-level assessment, exactly as the backend treats them.
struct EnrouteHazardsSection: View {
    let convective: TcfEnvelope?
    let internationalSigmets: [InternationalSigmet]?
    /// Embedded = rendered inside a CollapsibleSection's card: keeps its own
    /// sub-header (the title differs from the disclosure's) but drops the
    /// card shell so it doesn't nest a capsule inside a capsule.
    var embedded: Bool = false

    private var advisories: [InternationalSigmet] { internationalSigmets ?? [] }

    private var hasContent: Bool {
        convective != nil || !advisories.isEmpty
    }

    var body: some View {
        if hasContent {
            if embedded {
                sectionContent
            } else {
                sectionContent
                    .cardStyle()
            }
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "cloud-lightning", title: "Convective & en-route hazards")

            if let convective {
                convectiveBlock(convective)
            }

            if !advisories.isEmpty {
                if convective != nil {
                    Divider().overlay(Theme.hairline)
                }
                advisoryBlock
            }

            Text("Context only — these don't change the assessment above, the same way FAA traffic management treats them as inputs rather than decisions.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: - TCF

    @ViewBuilder
    private func convectiveBlock(_ tcf: TcfEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LucideIcon(name: tcf.isQuiet ? "sun" : "cloud-lightning", size: 15,
                           fallback: tcf.isQuiet ? "sun.max" : "cloud.bolt")
                    .foregroundStyle(levelTone(tcf).color)
                GlossaryText(text: "TCF thunderstorm forecast",
                             font: .caption.weight(.semibold),
                             color: Theme.ink)
                Spacer()
                StatusChip(text: tcf.isQuiet ? "Clear" : tcf.level,
                           tone: levelTone(tcf), size: .mini, uppercased: true)
            }

            Text(convectiveHeadline(tcf))
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !tcf.isQuiet {
                HStack(spacing: 6) {
                    ForEach(placementChips(tcf), id: \.self) { chip in
                        StatusChip(text: chip, tone: .info, size: .mini)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The empty case is the norm, so it gets a confident sentence rather than
    /// an absence of information.
    private func convectiveHeadline(_ tcf: TcfEnvelope) -> String {
        guard !tcf.isQuiet else {
            return "No forecast convective area anywhere near your route — the usual, and the good outcome."
        }
        let count = tcf.areas.count
        let noun = count == 1 ? "area" : "areas"
        let coverage = tcf.level == "MODERATE"
            ? "Medium coverage — this is the kind of forecast the FAA reroutes or ground-stops around."
            : "Sparse coverage — usually reroutes and vectors rather than ground stops."
        return "\(count) forecast storm \(noun) intersecting your route. \(coverage)"
    }

    private func placementChips(_ tcf: TcfEnvelope) -> [String] {
        var chips: [String] = []
        if tcf.nearOriginCount > 0 { chips.append("Near departure") }
        if tcf.nearDestCount > 0 { chips.append("Near arrival") }
        if tcf.alongRouteCount > 0 { chips.append("\(tcf.alongRouteCount) en route") }
        if let tops = tcf.maxTopsHundredsFt { chips.append("Tops \(tops * 100) ft") }
        return chips
    }

    private func levelTone(_ tcf: TcfEnvelope) -> ChipTone {
        guard !tcf.isQuiet else { return .ok }
        switch tcf.level {
        case "MODERATE": return .watch
        case "HIGH", "SEVERE": return .alert
        default: return .info
        }
    }

    // MARK: - International SIGMETs

    private var advisoryBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LucideIcon(name: "globe", size: 15, fallback: "globe")
                    .foregroundStyle(Theme.teal)
                GlossaryText(text: "International SIGMETs",
                             font: .caption.weight(.semibold),
                             color: Theme.ink)
                Spacer()
                Text("\(advisories.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Text("Active advisories in the airspace regions your airports sit in — a regional list, not a route-intersection test.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)

            ForEach(Array(advisories.prefix(4).enumerated()), id: \.offset) { _, advisory in
                HStack(alignment: .top, spacing: 8) {
                    LucideIcon(name: "triangle-alert", size: 12, fallback: "exclamationmark.triangle")
                        .foregroundStyle(Theme.gold)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        GlossaryText(text: advisory.headline,
                                     font: .caption.weight(.semibold),
                                     color: Theme.ink)
                        Text(advisorySubline(advisory))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            if advisories.count > 4 {
                Text("+ \(advisories.count - 4) more in these regions")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func advisorySubline(_ advisory: InternationalSigmet) -> String {
        var parts: [String] = []
        if let fir = advisory.firDisplay { parts.append("\(fir) FIR") }
        if let band = advisory.altitudeBand { parts.append(band) }
        if let until = TimeFmt.parseISO(advisory.validTo) {
            parts.append("until \(TimeFmt.clock(advisory.validTo)) (\(TimeFmt.relative(until)))")
        }
        return parts.isEmpty ? "Active advisory" : parts.joined(separator: " · ")
    }
}
