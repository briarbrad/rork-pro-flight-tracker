import SwiftUI

/// Answers "will this delay grow, shrink, or hold steady" directly under the
/// trip timeline — the question the app previously only answered inside the
/// collapsed analyst narrative, if at all.
///
/// Two independent rows, each omitted entirely when it has nothing real:
///  - **Trend** — the server-recorded delta series across the background
///    tracker's scheduled checks ("+2 → +4 → +4 min over the last 3 checks —
///    holding steady"). Direction is classified server-side; the client
///    renders it verbatim and never re-derives a trend. One check = no row,
///    never a false "holding steady".
///  - **Outlook** — the analyst narrative's own forward-looking line
///    (its "What Would Change the Picture" item), promoted verbatim from
///    fresh briefs only. The client never invents advice.
struct DelayOutlookView: View {
    let trend: BriefDelayTrend?
    let outlook: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = trendLine, let direction = trend?.directionCode {
                trendRow(line: line, direction: direction)
            }
            if let outlook, !outlook.isEmpty {
                outlookRow(outlook)
            }
        }
        .padding(12)
        .background(Theme.teal.opacity(0.05))
        .clipShape(.rect(cornerRadius: Theme.Radius.well))
    }

    /// Whether this view would render anything — callers gate on this so an
    /// empty well never appears.
    static func hasContent(trend: BriefDelayTrend?, outlook: String?) -> Bool {
        (trend?.hasTrend ?? false) || !(outlook ?? "").isEmpty
    }

    // MARK: - Trend row

    private func trendRow(line: String, direction: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            LucideIcon(name: trendIcon(direction), size: 12,
                       fallback: "chart.line.uptrend.xyaxis")
                .foregroundStyle(trendColor(direction))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Delay trend")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary)
                Text(line)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(trendColor(direction))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "+2 → +4 → +4 min over the last 3 checks — holding steady".
    /// Built from the last few server snapshots, oldest first.
    private var trendLine: String? {
        guard let trend, trend.hasTrend else { return nil }
        let deltas = trend.orderedSnapshots.compactMap { $0.deltaMinutes }.suffix(4)
        guard deltas.count >= 2, let direction = trend.directionCode else { return nil }
        let series = deltas.map(formatDelta).joined(separator: " → ")
        let checks = deltas.count
        return "\(series) min over the last \(checks) checks — \(directionLabel(direction))"
    }

    private func formatDelta(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        if rounded > 0 { return "+\(rounded)" }
        return "\(rounded)"
    }

    private func directionLabel(_ direction: String) -> String {
        switch direction {
        case "widening": return "getting worse"
        case "narrowing": return "improving"
        default: return "holding steady"
        }
    }

    private func trendIcon(_ direction: String) -> String {
        switch direction {
        case "widening": return "trending-up"
        case "narrowing": return "trending-down"
        default: return "move-right"
        }
    }

    private func trendColor(_ direction: String) -> Color {
        switch direction {
        case "widening": return Theme.red
        case "narrowing": return Theme.greenText
        default: return Theme.inkSecondary
        }
    }

    // MARK: - Outlook row

    private func outlookRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            LucideIcon(name: "telescope", size: 12, fallback: "binoculars")
                .foregroundStyle(Theme.teal)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Outlook — what could change this")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary)
                GlossaryText(text: text, font: .caption, color: Theme.ink)
            }
        }
    }
}
