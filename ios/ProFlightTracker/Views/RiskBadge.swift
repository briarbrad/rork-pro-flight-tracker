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
/// live verdict governs. A status-only LOW is "nothing visible in status
/// data", not "all clear": it NEVER wears the reassuring "Low risk" chip —
/// only the full brief analysis may claim genuinely low risk. Instead it
/// renders as a neutral, clearly informational "Status only / analysis
/// pending" pill.
struct FlightVerdictBadge: View {
    let brief: StoredBrief?
    let live: StoredLive?
    /// When true (flight detail screen), tapping the verdict chip opens the
    /// glossary definition of "Watch" / "Low risk" / "High risk" — same
    /// mechanism as tapping GDP or EDCT in prose. Off by default so list
    /// rows inside NavigationLinks keep their whole-row tap.
    var defineOnTap: Bool = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let brief {
            if let liveLevel = live?.riskLevel, overridesBrief(brief, liveLevel: liveLevel) {
                livePill(liveLevel)
            } else {
                BriefVerdictBadge(brief: brief, defineOnTap: defineOnTap)
            }
        } else if let liveLevel = live?.riskLevel {
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

    /// Status-only verdicts see cancellations, diversions, slips, and EDCTs
    /// — but no weather or FAA-program analysis. An elevated verdict is a
    /// real warning and gets its severity chip; a LOW one is incomplete data,
    /// so it renders neutral and informational, never as "Low risk".
    @ViewBuilder
    private func livePill(_ level: RiskLevel) -> some View {
        if level.rank > RiskLevel.low.rank {
            VStack(alignment: .trailing, spacing: 2) {
                definableChip(text: level.label, icon: level.lucideIcon,
                              tone: .from(level), term: level.label)

                Text("Live status")
                    .font(TypeScale.kicker)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary)
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                StatusChip(text: "Status only", icon: "hourglass", tone: .neutral)

                Text("Analysis pending")
                    .font(TypeScale.kicker)
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private func definableChip(text: String, icon: String, tone: ChipTone,
                               term: String) -> some View {
        if defineOnTap, FAAGlossary.entry(for: term) != nil {
            Button {
                Haptics.tap()
                if let url = FAAGlossary.url(for: term) { openURL(url) }
            } label: {
                StatusChip(text: text, icon: icon, tone: tone)
            }
            .buttonStyle(.plain)
        } else {
            StatusChip(text: text, icon: icon, tone: tone)
        }
    }
}

/// The brief-driven verdict pill. Neutral (gray) for too-early /
/// low-confidence states so "nothing visible yet" never masquerades as
/// "all clear".
struct BriefVerdictBadge: View {
    let brief: StoredBrief
    /// See `FlightVerdictBadge.defineOnTap`.
    var defineOnTap: Bool = false

    @Environment(\.openURL) private var openURL

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
            // Neutral pills ("Too early", "No signal yet") have no glossary
            // entry — only real verdict words become tappable definitions.
            if defineOnTap, !brief.isNeutral, let level = brief.riskLevel,
               FAAGlossary.entry(for: level.label) != nil {
                Button {
                    Haptics.tap()
                    if let url = FAAGlossary.url(for: level.label) { openURL(url) }
                } label: {
                    StatusChip(text: text, icon: icon, tone: tone)
                }
                .buttonStyle(.plain)
            } else {
                StatusChip(text: text, icon: icon, tone: tone)
            }

            if let confidence = brief.confidence {
                confidenceLine(confidence)
            }
        }
    }

    /// "High confidence" is the most-misread label in the app — on the
    /// detail screen it taps through to the glossary entry that says plainly:
    /// confidence tracks the departure horizon, not certainty in the numbers.
    @ViewBuilder
    private func confidenceLine(_ confidence: String) -> some View {
        let label = Text("\(confidence.capitalized) confidence")
            .font(TypeScale.kicker)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.inkSecondary)
        if defineOnTap {
            Button {
                Haptics.tap()
                if let url = FAAGlossary.url(for: "CONFIDENCE") { openURL(url) }
            } label: {
                HStack(spacing: 3) {
                    label
                    LucideIcon(name: "info", size: 9, fallback: "info.circle")
                        .foregroundStyle(Theme.teal)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(confidence.capitalized) confidence. Tap for what confidence means.")
        } else {
            label
        }
    }
}
