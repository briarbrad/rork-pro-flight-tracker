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
                    .font(TypeScale.kicker)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary)
                Text(line)
                    .font(TypeScale.captionStrong)
                    .monospacedDigit()
                    .foregroundStyle(trendColor(direction))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let points = sparklinePoints {
                DelaySparkline(values: points, color: trendColor(direction))
                    .padding(.top, 4)
            }
        }
    }

    /// Last few server snapshots, oldest first — only drawn when there are
    /// at least two numeric deltas (same gate as `hasTrend`).
    private var sparklinePoints: [Double]? {
        guard let trend, trend.hasTrend else { return nil }
        let values = trend.orderedSnapshots.compactMap(\.deltaMinutes).suffix(6)
        return values.count >= 2 ? Array(values) : nil
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
                    .font(TypeScale.kicker)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary)
                GlossaryText(text: text, font: .caption, color: Theme.ink)
            }
        }
    }
}

/// Tiny delay-delta sparkline. Fits the well without becoming a chart.
struct DelaySparkline: View {
    let values: [Double]
    var color: Color = Theme.teal

    /// Normalized 0…1 points, oldest first — used by tests and the path.
    static func normalized(_ values: [Double]) -> [CGFloat] {
        guard let minV = values.min(), let maxV = values.max() else { return [] }
        let span = max(maxV - minV, 1)
        return values.map { CGFloat(($0 - minV) / span) }
    }

    var body: some View {
        Canvas { context, size in
            let points = Self.normalized(values)
            guard points.count >= 2 else { return }
            var path = Path()
            for (index, unit) in points.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let y = size.height * (1 - unit)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 56, height: 16)
        .accessibilityHidden(true)
    }
}
