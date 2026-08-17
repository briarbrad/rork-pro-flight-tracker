import SwiftUI

/// Pill-shaped risk indicator that subtly animates when severity changes.
struct RiskBadge: View {
    let level: RiskLevel

    @State private var pulse: Bool = false

    var body: some View {
        StatusChip(text: level.label, icon: level.lucideIcon, tone: .from(level))
            .scaleEffect(pulse ? 1.12 : 1.0)
            .onChange(of: level) { _, _ in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pulse = true }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.15)) { pulse = false }
            }
    }
}

/// Flight-level verdict pill with the live/brief precedence rule encoded:
/// the brief is authoritative for weather/program risk while fresh — the
/// live status_only verdict (cancellations, diversions, slips, EDCTs) may
/// only ESCALATE over it, never soften it. Once the brief goes stale, the
/// live verdict governs. With no brief at all, only an elevated live verdict
/// earns a pill — a status-only LOW is "nothing visible in status data",
/// not "all clear", and must not wear a reassuring badge.
struct FlightVerdictBadge: View {
    let brief: StoredBrief?
    let live: StoredLive?

    var body: some View {
        if let brief {
            if let liveLevel = live?.riskLevel, overridesBrief(brief, liveLevel: liveLevel) {
                livePill(liveLevel)
            } else {
                BriefVerdictBadge(brief: brief)
            }
        } else if let liveLevel = live?.riskLevel, liveLevel.rank > RiskLevel.low.rank {
            livePill(liveLevel)
        }
    }

    private func overridesBrief(_ brief: StoredBrief, liveLevel: RiskLevel) -> Bool {
        let briefRank = brief.riskLevel?.rank ?? 0
        // Fresh brief: live may only escalate over it.
        guard brief.isStale else { return liveLevel.rank > briefRank }
        // Stale brief: the live verdict governs whenever it differs.
        return liveLevel.rank != briefRank
    }

    private func livePill(_ level: RiskLevel) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            StatusChip(text: level.label, icon: level.lucideIcon, tone: .from(level))

            Text("Live status")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

/// The brief-driven verdict pill. Neutral (gray) for too-early /
/// low-confidence states so "nothing visible yet" never masquerades as
/// "all clear".
struct BriefVerdictBadge: View {
    let brief: StoredBrief

    var body: some View {
        let tone: ChipTone = brief.isNeutral
            ? .neutral
            : (brief.riskLevel.map(ChipTone.from) ?? .neutral)
        let icon: String = brief.isNeutral ? "hourglass" : (brief.riskLevel?.lucideIcon ?? "shield")
        let text: String = {
            if brief.isTooEarly { return "Too early" }
            if brief.isNeutral { return "No signal yet" }
            return brief.riskLevel?.label ?? (brief.risk ?? "—")
        }()

        VStack(alignment: .trailing, spacing: 2) {
            StatusChip(text: text, icon: icon, tone: tone)

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
