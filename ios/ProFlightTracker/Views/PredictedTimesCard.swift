import SwiftUI

/// Headline of the flight screen after a brief runs: the server-predicted
/// Gate / Takeoff / Arrival times with schedule deltas and provenance.
/// Times and statuses are computed upstream and never recomputed here; the only
/// client-side work is falling back to the bundled airport-zone table when the
/// backend couldn't resolve a zone. Gate and takeoff read in the origin's local
/// time, arrival in the destination's. Tapping an entry reveals its `basis`.
struct PredictedTimesCard: View {
    let times: BriefPredictedTimes
    var timezones: BriefTimezones? = nil
    var zones: FlightZones = .unknown
    /// Stale treatment, mirroring the verdict card: dimmed content, "as of"
    /// caption, and a user-initiated affordance. Never auto-refreshes.
    var isStale: Bool = false
    var runAt: Date? = nil
    /// "refresh" when the live layer drives this card, "re-run the brief"
    /// when the brief fallback does.
    var staleVerb: String = "re-run the brief"
    var onRerun: (() -> Void)? = nil

    @State private var expandedSlot: PredictedSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "clock-arrow-down", title: "Predicted times")

            HStack(alignment: .top, spacing: 0) {
                entryColumn(.gate, entry: times.gateDeparture)
                divider
                entryColumn(.takeoff, entry: times.takeoff)
                divider
                entryColumn(.arrival, entry: times.gateArrival)
            }

            if let expandedSlot, let basis = entry(for: expandedSlot)?.basis {
                basisReveal(slot: expandedSlot, basis: basis)
            }

            if let zoneCaption {
                HStack(spacing: 5) {
                    LucideIcon(name: "globe", size: 10, fallback: "globe")
                    Text(zoneCaption)
                }
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
            }

            if let note = times.uncertaintyNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }

            // One freshness language: "as of Xm ago", amber with the
            // user-initiated refresh affordance once past the window.
            if let runAt {
                FreshnessCaption(asOf: runAt,
                                 isStale: isStale,
                                 staleHint: "\(staleVerb) for the live picture.",
                                 onAction: onRerun)
            }
        }
        .opacity(isStale ? 0.75 : 1)
        .cardStyle()
    }

    private var originZone: TimeZone? {
        AirportTimeZones.named(timezones?.origin ?? times.gateDeparture?.timezone) ?? zones.origin
    }

    private var destinationZone: TimeZone? {
        AirportTimeZones.named(timezones?.destination ?? times.gateArrival?.timezone) ?? zones.destination
    }

    /// Makes the two-zone rule explicit: departure times are origin-local,
    /// arrival is destination-local (a JFK→Paris arrival reads in Paris time).
    private var zoneCaption: String? {
        let origin = AirportTimeZones.cityName(originZone)
        let dest = AirportTimeZones.cityName(destinationZone)
        switch (origin, dest) {
        case let (origin?, dest?) where origin != dest:
            return "Departure in \(origin) time · arrival in \(dest) time"
        case let (origin?, _):
            return "Local time at \(origin)"
        case let (nil, dest?):
            return "Arrival in \(dest) time"
        default:
            return "Times shown in Zulu — airport zone unavailable"
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private func entry(for slot: PredictedSlot) -> BriefPredictedTime? {
        switch slot {
        case .gate: return times.gateDeparture
        case .takeoff: return times.takeoff
        case .arrival: return times.gateArrival
        }
    }

    /// Departure-side slots belong to the origin, arrival to the destination.
    private func zone(for slot: PredictedSlot) -> TimeZone? {
        slot == .arrival ? destinationZone : originZone
    }

    @ViewBuilder
    private func entryColumn(_ slot: PredictedSlot, entry: BriefPredictedTime?) -> some View {
        let hasBasis = entry?.basis != nil
        Button {
            guard hasBasis else { return }
            Haptics.tap()
            withAnimation(.snappy) {
                expandedSlot = expandedSlot == slot ? nil : slot
            }
        } label: {
            VStack(spacing: 5) {
                Text(slot.label(isActual: entry?.isActual == true))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.inkSecondary)

                timeText(entry, zone: zone(for: slot))

                deltaChip(entry)

                if hasBasis {
                    LucideIcon(name: expandedSlot == slot ? "chevron-up" : "chevron-down",
                               size: 10, fallback: "chevron.down")
                        .foregroundStyle(Theme.hairline)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!hasBasis)
    }

    /// Status vocabulary: ACTUAL plain past tense · CONTROLLED strongest
    /// highlight (FAA-assigned beats airline estimates) · ESTIMATED/DERIVED
    /// normal · SCHEDULED muted · UNKNOWN em dash.
    @ViewBuilder
    private func timeText(_ entry: BriefPredictedTime?, zone: TimeZone?) -> some View {
        if entry == nil || entry?.isUnknown == true {
            Text("—")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
        } else if entry?.isControlled == true {
            VStack(spacing: 2) {
                // FAA-authoritative fact — the ONLY place the solid style is
                // allowed besides the EDCT banner.
                StatusChip(text: entry?.displayTime(fallbackZone: zone) ?? "—",
                           tone: .info, size: .mini, style: .solid)
                Text("FAA slot")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.tealDeep)
            }
        } else {
            Text(entry?.displayTime(fallbackZone: zone) ?? "—")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(entry?.isScheduledOnly == true ? Theme.inkSecondary : Theme.ink)
        }
    }

    @ViewBuilder
    private func deltaChip(_ entry: BriefPredictedTime?) -> some View {
        // An actual time is a fact, not a promise — the reassuring green
        // "on time" chip is for predictions only. A late actual (+N min)
        // remains factual and stays.
        if let delay = entry?.delayVsScheduleMin, entry?.isUnknown != true,
           !(entry?.isActual == true && delay <= 0) {
            let late = delay > 0
            // Late deltas escalate on the shared thresholds — a +50 min slip
            // reads red here for the same reason it reads red everywhere.
            let tone: ChipTone = late
                ? (SlipSeverity.of(minutes: Double(delay)) == .alert ? .alert : .watch)
                : .ok
            StatusChip(text: late ? "+\(delay) min" : "on time", tone: tone, size: .mini)
        }
    }

    private func basisReveal(slot: PredictedSlot, basis: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(slot.label(isActual: false)) — how this was computed")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.ink)
            GlossaryText(text: basis, font: .caption2, color: Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: Theme.Radius.well))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

enum PredictedSlot: Hashable {
    case gate, takeoff, arrival

    func label(isActual: Bool) -> String {
        switch self {
        case .gate: return isActual ? "Departed" : "Gate"
        case .takeoff: return isActual ? "Took off" : "Takeoff"
        case .arrival: return isActual ? "Arrived" : "Arrival"
        }
    }
}

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

    @State private var showInfo: Bool = false

    private var primary: [BriefEffect] { effects.filter { $0.severityCode != "INFO" } }
    private var info: [BriefEffect] { effects.filter { $0.severityCode == "INFO" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's affecting this flight")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)

            if primary.isEmpty && !info.isEmpty {
                Text("Nothing is directly acting on this flight — context below.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
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
