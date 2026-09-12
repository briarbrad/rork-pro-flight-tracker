import SwiftUI

/// Single story hero. Locked binding — no parallel status/forecast layouts:
/// - `outlook.applicable` → `outlook.headline`
/// - else → `simple_summary` (designed prediction chrome) + `status.label`
///   + `impactMinutes` as the subtitle
/// Cause rows sit in this same card only when the list is non-empty.
struct FlightStoryCard: View {
    let story: FlightStory
    /// Designed `simple_summary` fallback when the server omitted the object.
    var fallbackPrediction: SimplePrediction? = nil
    var asOf: Date? = nil
    var isStale: Bool = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if story.usesOutlook {
                outlookHero
            } else {
                summaryHero
            }

            if story.hasCauses {
                Divider().overlay(Theme.hairline)
                CauseChainView(causes: story.orderedCauses,
                               title: story.usesOutlook
                                   ? "What's on the forecast"
                                   : "Why this flight")
            }

            if let asOf {
                FreshnessCaption(asOf: asOf, isStale: isStale,
                                 staleHint: "refresh for the current picture.",
                                 onAction: onRefresh)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var outlookHero: some View {
        Text(story.heroHeadline ?? "Looking ahead")
            .font(TypeScale.headline)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)

        if let confidence = story.outlook?.confidence?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !confidence.isEmpty {
            Text("\(confidence.capitalized) confidence — a forecast, not a hard delay.")
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var summaryHero: some View {
        Text("Based on what I know")
            .font(TypeScale.kicker)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.teal)

        Text("Here's what I think will happen")
            .font(TypeScale.caption)
            .foregroundStyle(Theme.inkSecondary)

        Text(story.heroHeadline
             ?? (story.simpleSummary == nil ? fallbackPrediction?.headline : nil)
             ?? "Checking this flight")
            .font(TypeScale.headline)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)

        if let body = story.heroBody, !body.isEmpty {
            Text(body)
                .font(TypeScale.sectionTitle)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        } else if story.simpleSummary == nil, let body = fallbackPrediction?.body, !body.isEmpty {
            Text(body)
                .font(TypeScale.sectionTitle)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let sub = story.statusSubline {
            Text(sub)
                .font(TypeScale.captionStrong)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Cause rows: bold label, short why. ACTION / WATCH / INFO change type
/// weight and ink — no chips, icons, or other chrome.
struct CauseChainView: View {
    let causes: [StoryCause]
    var title: String = "Why this flight"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(TypeScale.captionBold)
                .foregroundStyle(Theme.ink)

            ForEach(Array(causes.enumerated()), id: \.offset) { _, cause in
                CauseRow(cause: cause)
            }
        }
    }
}

struct CauseRow: View {
    let cause: StoryCause

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cause.label ?? "Something to watch")
                .font(labelFont)
                .foregroundStyle(labelColor)
                .fixedSize(horizontal: false, vertical: true)
            if let why = cause.why, !why.isEmpty {
                Text(why)
                    .font(TypeScale.caption)
                    .foregroundStyle(whyColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Heavier weight = more urgent. Color tints the same scale.
    private var labelFont: Font {
        switch cause.severityCode {
        case "ACTION": return TypeScale.captionBold
        case "WATCH": return TypeScale.captionStrong
        default: return TypeScale.caption
        }
    }

    private var labelColor: Color {
        switch cause.severityCode {
        case "ACTION": return Theme.red
        case "WATCH": return Theme.goldText
        default: return Theme.ink
        }
    }

    private var whyColor: Color {
        switch cause.severityCode {
        case "ACTION", "WATCH": return Theme.ink
        default: return Theme.inkSecondary
        }
    }

    private var accessibilityText: String {
        [cause.label ?? "Something to watch", cause.severitySpoken, cause.why ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}
