import SwiftUI

/// FAA-assigned wheels-up slot — the single most important fact on the screen
/// when present. Styled as an authoritative statement, visually distinct from
/// every estimate. Rendered only when the backend sends a non-null edct.
struct EdctBanner: View {
    let edct: BriefEdct
    /// The departure airport's zone — an EDCT is always a wheels-up time there.
    var originZone: TimeZone? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LucideIcon(name: "tower-control", size: 22, fallback: "antenna.radiowaves.left.and.right")
                .foregroundStyle(Theme.gold)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("FAA assigned takeoff slot")
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.gold)
                Text("\(edct.displayTime(fallbackZone: originZone)) (±5 min)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(sublineText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.92))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tealDeep)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .cardShadow()
    }

    private var sublineText: String {
        var parts: [String] = ["Controlled wheels-up time — not an estimate"]
        if let via = edct.assignedVia { parts.append("via \(via)") }
        if let asOf = edct.asOf { parts.append("as of \(TimeFmt.relative(TimeFmt.parseISO(asOf) ?? Date()))") }
        return parts.joined(separator: " · ")
    }
}

/// The primary explanation of the flight's situation: every backend finding
/// as cause → effect on THIS flight. Severities are server-computed (a GDP at
/// the origin arrives as INFO for a departure) and are never re-derived here.
/// INFO items collapse behind "More context (N)".
struct EffectsList: View {
    let effects: [BriefEffect]
    /// Set when a delta chip is visible elsewhere on the screen but the brief
    /// found no cause for it — the "nothing acting on this flight" copy then
    /// explicitly accounts for the visible slip instead of contradicting it.
    var unexplainedDeltaNote: String? = nil

    @State private var showInfo: Bool = false

    private var primary: [BriefEffect] { effects.filter { $0.severityCode != "INFO" } }
    private var info: [BriefEffect] { effects.filter { $0.severityCode == "INFO" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's affecting this flight")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)

            if primary.isEmpty && !info.isEmpty {
                // "No cause found" is NOT "nothing to worry about" — the
                // copy says which one this is, and owns any visible delta.
                Text(unexplainedDeltaNote
                     ?? "No active cause identified in the sources checked — context below.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(primary.enumerated()), id: \.offset) { _, effect in
                EffectRow(effect: effect)
            }

            if !info.isEmpty {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { showInfo.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        LucideIcon(name: "info", size: 12, fallback: "info.circle")
                        Text("More context (\(info.count))")
                            .font(.caption2.weight(.semibold))
                        LucideIcon(name: showInfo ? "chevron-up" : "chevron-down",
                                   size: 11, fallback: "chevron.down")
                    }
                    .foregroundStyle(Theme.inkSecondary)
                }
                if showInfo {
                    ForEach(Array(info.enumerated()), id: \.offset) { _, effect in
                        EffectRow(effect: effect)
                    }
                }
            }
        }
    }
}

/// One cause → effect row. Cause is the bold line, effect the body.
struct EffectRow: View {
    let effect: BriefEffect

    private var color: Color {
        switch effect.severityCode {
        case "ACTION": return Theme.red
        case "WATCH": return Theme.gold
        default: return Theme.inkSecondary
        }
    }

    private var icon: String {
        switch effect.severityCode {
        case "ACTION": return "octagon-alert"
        case "WATCH": return "eye"
        default: return "info"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.13))
                    .frame(width: 30, height: 30)
                LucideIcon(name: icon, size: 14, fallback: "info.circle")
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 6) {
                    GlossaryText(text: effect.cause ?? "Finding",
                                 font: .caption.weight(.semibold),
                                 color: Theme.ink)
                    if effect.severityCode != "INFO" {
                        StatusChip(text: effect.severityCode,
                                   tone: effect.severityCode == "ACTION" ? .alert : .watch,
                                   size: .mini, uppercased: true)
                    }
                }
                if let body = effect.effect {
                    GlossaryText(text: body, font: .caption2, color: Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
