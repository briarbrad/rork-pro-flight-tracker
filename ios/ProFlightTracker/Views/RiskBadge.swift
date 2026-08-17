import SwiftUI

/// Pill-shaped risk indicator that subtly animates when severity changes.
struct RiskBadge: View {
    let level: RiskLevel
    var compact: Bool = false

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            LucideIcon(name: level.lucideIcon, size: compact ? 12 : 14,
                       fallback: "shield")
            if !compact {
                Text(level.label)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(level.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(level.color.opacity(0.14))
        .clipShape(.capsule)
        .scaleEffect(pulse ? 1.12 : 1.0)
        .onChange(of: level) { _, _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pulse = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.15)) { pulse = false }
        }
    }
}

/// The flight-level verdict pill — driven exclusively by the last /api/brief
/// run. Neutral (gray) for too-early / low-confidence states so "nothing
/// visible yet" never masquerades as "all clear".
struct BriefVerdictBadge: View {
    let brief: StoredBrief

    var body: some View {
        let color: Color = brief.isNeutral ? Theme.inkSecondary : (brief.riskLevel?.color ?? Theme.inkSecondary)
        let icon: String = brief.isNeutral ? "hourglass" : (brief.riskLevel?.lucideIcon ?? "shield")
        let text: String = {
            if brief.isTooEarly { return "Too early" }
            if brief.isNeutral { return "No signal yet" }
            return brief.riskLevel?.label ?? (brief.risk ?? "—")
        }()

        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 5) {
                LucideIcon(name: icon, size: 12, fallback: "shield")
                Text(text)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.13))
            .clipShape(.capsule)

            if let confidence = brief.confidence {
                Text("\(confidence.capitalized) confidence")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }
}
