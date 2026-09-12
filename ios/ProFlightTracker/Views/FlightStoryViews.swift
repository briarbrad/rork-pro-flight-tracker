import SwiftUI

/// Hero for the flight story layer: outlook when `applicable`, otherwise
/// status.label + impactMinutes. Cause rows sit directly under the headline
/// so the screen reads "this is delayed because X".
struct FlightStoryCard: View {
    let story: FlightStory

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(story.usesOutlook ? "Forecast" : "Status")
                .font(TypeScale.kicker)
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.teal)

            if story.usesOutlook {
                outlookHero
            } else {
                liveHero
            }

            if story.hasCauses {
                Divider().overlay(Theme.hairline)
                CauseChainView(causes: story.orderedCauses,
                               title: story.usesOutlook
                                   ? "What's on the forecast"
                                   : "Why this flight")
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var outlookHero: some View {
        let outlook = story.outlook
        Text(outlook?.headline ?? "Looking ahead")
            .font(TypeScale.headline)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
            if let risk = outlook?.risk {
                StatusChip(text: risk.label, icon: risk.lucideIcon,
                           tone: ChipTone.from(risk))
            }
            if let confidence = outlook?.confidence, !confidence.isEmpty {
                StatusChip(text: "\(confidence.capitalized) confidence",
                           tone: outlook?.isLowConfidence == true ? .neutral : .info,
                           size: .mini)
            }
            Spacer(minLength: 0)
        }

        if let label = story.status?.displayLabel {
            Text("Status · \(label)")
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    @ViewBuilder
    private var liveHero: some View {
        Text(story.status?.displayLabel ?? "Checking this flight")
            .font(TypeScale.headline)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
            if let minutes = story.impactMinutes {
                impactChip(minutes)
            } else if let status = story.status, status.statusCode != "UNKNOWN" {
                StatusChip(text: status.statusCode.replacingOccurrences(of: "_", with: " ").capitalized,
                           tone: status.chipTone, size: .mini)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func impactChip(_ minutes: Int) -> some View {
        if minutes > 0 {
            StatusChip(text: "+\(minutes) min vs schedule",
                       tone: SlipSeverity.of(minutes: Double(minutes)) == .alert ? .alert : .watch,
                       size: .mini)
        } else if minutes < 0 {
            StatusChip(text: "\(minutes) min vs schedule",
                       tone: .ok, size: .mini)
        } else {
            StatusChip(text: "On schedule", tone: .ok, size: .mini)
        }
    }
}

/// Cause rows: bold label, short why, spoken severity (not color-only).
struct CauseChainView: View {
    let causes: [StoryCause]
    var title: String = "Why this flight"
    var embedded: Bool = true

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(TypeScale.captionBold)
                .foregroundStyle(Theme.ink)

            ForEach(Array(causes.enumerated()), id: \.offset) { _, cause in
                CauseRow(cause: cause)
            }
        }

        if embedded {
            content
        } else {
            content.cardStyle()
        }
    }
}

struct CauseRow: View {
    let cause: StoryCause

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(cause.chipTone.color.opacity(0.13))
                    .frame(width: 30, height: 30)
                LucideIcon(name: cause.icon, size: 14, fallback: "info.circle")
                    .foregroundStyle(cause.chipTone.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(cause.label ?? "Something to watch")
                        .font(TypeScale.captionBold)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    // Text names the severity so color is never the only cue.
                    StatusChip(text: cause.severityLabel,
                               tone: cause.chipTone,
                               size: .mini)
                }
                if let why = cause.why, !why.isEmpty {
                    Text(why)
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = cause.label ?? "Something to watch"
        let why = cause.why ?? ""
        return [name, cause.severityLabel, why]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}
