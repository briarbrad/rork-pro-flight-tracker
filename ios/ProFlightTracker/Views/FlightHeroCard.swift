import SwiftUI

/// The ONE status card at the top of the flight screen — replaces the old
/// header / phase-card / verdict-badge competition where status appeared four
/// different ways. Reads from the freshest phase layer (the single source of
/// truth): route, the phase pill, the next event and its predicted time
/// ("Landing · ~8:43 AM"), the flight-level verdict badge, and the unified
/// trip timeline — the single place ALL milestone timing (scheduled /
/// estimated / actual, deltas, gates) renders. The raw airline status string
/// is a small subtitle, never a headline.
struct FlightHeroCard: View {
    let leg: AeroFlight?
    /// Truth phase: live layer → brief (before the first live pull) →
    /// milestone-derived guard.
    let phase: BriefPhase?
    let taxi: BriefTaxi?
    let position: BriefPosition?
    /// Predicted-times entry behind `phase.next_event`, for the time and
    /// delta fallback when the server didn't send a resolved display.
    let nextEventEntry: BriefPredictedTime?
    let brief: StoredBrief?
    let live: StoredLive?
    let zones: FlightZones
    /// SOURCE-pull anchor — countdowns and elapsed-in-phase advance from
    /// this with wall-clock time, and the freshness caption renders from it.
    let asOf: Date?
    let isStale: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            if phase?.isCancelled == true {
                cancelledRow
            } else if phase?.isOver != true {
                nextEventBlock
            }

            // The airline's raw status string ("Arrived / Gate Arrival") is a
            // footnote, not a headline — the phase layer is the state.
            if let status = leg?.status, !status.isEmpty {
                Text("Airline status · \(status)")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }

            Divider().overlay(Theme.hairline)

            timeline

            // Taxi assessment — whether this wait is abnormal for THIS
            // airport. Summary is server-written, rendered verbatim.
            if let taxi, taxi.isApplicable {
                taxiBlock(taxi)
            }

            // Live position — only when something is actually reported.
            // Patchy surface ADS-B is missing data, not a problem.
            if let position, position.isAvailable {
                positionRow(position)
            }

            if let asOf {
                FreshnessCaption(asOf: asOf, isStale: isStale,
                                 staleHint: "refresh for the current picture.",
                                 onAction: onRefresh)
            }
        }
        .cardStyle()
    }

    // MARK: - Header: route + phase pill + verdict badge

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(leg?.originCity ?? leg?.originDisplay ?? "—") → \(leg?.destCity ?? leg?.destDisplay ?? "—")")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                HStack(spacing: 8) {
                    if let phase {
                        StatusChip(text: phase.phaseLabel ?? phase.code.capitalized,
                                   icon: phaseIcon(phase), tone: phaseTone(phase))
                    }
                    if let elapsed = elapsedInPhaseMinNow, phase?.isEnRoute == true {
                        Text("started \(durationText(elapsed)) ago")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: elapsed)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            Spacer()
            // Brief verdict is authoritative while fresh; the live
            // status_only verdict may escalate over it, and governs once
            // the brief goes stale.
            FlightVerdictBadge(brief: brief, live: live)
        }
    }

    // MARK: - Next event headline

    private var nextEventBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(phase?.nextEventLabel ?? "Next event")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .textCase(.uppercase)
                if phase?.isControlled == true {
                    // FAA-assigned time — materially harder than an estimate.
                    StatusChip(text: "FAA-controlled", tone: .watch, size: .mini,
                               uppercased: true)
                }
            }

            // The headline time never shrinks: when the countdown text is long
            // ("awaiting update — last predicted 10:45 PM EDT") the row stacks
            // vertically instead of scaling the time down.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    nextEventTimeView
                    countdownView
                    deltaChip
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        nextEventTimeView
                        deltaChip
                    }
                    countdownView
                }
            }

            if phase?.isOverdue == true {
                HStack(spacing: 6) {
                    LucideIcon(name: "trending-down", size: 12, fallback: "arrow.down.right")
                    Text("Overdue — the predicted time has passed and it hasn't happened yet.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.red)
            }

            if let basis = phase?.nextEventBasis, !basis.isEmpty {
                Text("Basis: \(basis)")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var nextEventTimeView: some View {
        Text(nextEventTimeText)
            .font(.system(.title2, design: .rounded).weight(.bold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: nextEventTimeText)
            .foregroundStyle(phase?.isOverdue == true ? Theme.red : Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var countdownView: some View {
        if let countdown = countdownText {
            Text(countdown)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: countdown)
                .foregroundStyle(phase?.isOverdue == true ? Theme.red : Theme.teal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cancelledRow: some View {
        HStack(spacing: 8) {
            LucideIcon(name: "circle-x", size: 14, fallback: "xmark.circle")
            Text(phase?.phaseDetail ?? "This flight has been cancelled.")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.red)
    }

    /// Delta vs schedule for the next event, on the shared slip thresholds.
    @ViewBuilder
    private var deltaChip: some View {
        if let delta = deltaMinutes {
            if delta > 0 {
                StatusChip(text: "+\(delta) min",
                           tone: SlipSeverity.of(minutes: Double(delta)) == .alert ? .alert : .watch,
                           size: .mini)
            } else {
                StatusChip(text: "on time", tone: .ok, size: .mini)
            }
        }
    }

    // MARK: - Unified trip timeline (the ONE timing display)

    /// Server predicted times: live layer wins on every refresh; the brief
    /// only feeds this before the first live pull.
    private var timelineTimes: BriefPredictedTimes? {
        live?.predictedTimes ?? brief?.predictedTimes
    }

    private var timeline: some View {
        TripTimelineView(leg: leg,
                         times: timelineTimes,
                         phase: phase,
                         zones: zones,
                         timezones: live?.timezones ?? brief?.timezones,
                         explainer: timelineExplainer)
    }

    /// One explainer instance drives the timeline's delta chips AND its
    /// inline explanation, so the two can never disagree.
    private var timelineExplainer: DeltaExplainer? {
        guard let times = timelineTimes else { return nil }
        let effects = live != nil ? (live?.effects ?? brief?.effects) : brief?.effects
        return DeltaExplainer(times: times, effects: effects)
    }

    // MARK: - Taxi assessment

    private func taxiBlock(_ taxi: BriefTaxi) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusChip(text: taxiLabel(taxi.assessmentCode),
                           tone: taxiTone(taxi.assessmentCode), size: .mini)
                Spacer()
                if let elapsed = taxi.elapsedMin, let typical = taxi.typicalMin {
                    Text("\(elapsed) min · typical \(typical)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            if let summary = taxi.summary, !summary.isEmpty {
                GlossaryText(text: summary, font: .caption, color: Theme.inkSecondary)
            }
        }
        .padding(12)
        .background(taxiTone(taxi.assessmentCode).color.opacity(0.06))
        .clipShape(.rect(cornerRadius: Theme.Radius.well))
    }

    // MARK: - Live position

    private func positionRow(_ position: BriefPosition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                LucideIcon(name: movementIcon(position.movementCode), size: 12,
                           fallback: "location")
                    .foregroundStyle(movementColor(position.movementCode))
                Text(position.movementLabel ?? "Position reported")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                if let speed = position.groundspeedKts, speed > 0 {
                    Text("\(Int(speed)) kt")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
            }
            if let note = position.note, !note.isEmpty {
                GlossaryText(text: note, font: .caption2, color: Theme.inkSecondary)
            }
        }
    }

    // MARK: - Derived values

    /// Which zone the next event reads in — arrival is destination-local,
    /// everything before it origin-local.
    private var nextEventZone: TimeZone? {
        phase?.nextEvent == "gate_arrival" ? zones.destination : zones.origin
    }

    /// Leg milestone behind the next event, for the no-live/no-brief fallback.
    private var fallbackNextEventISO: String? {
        switch phase?.nextEvent {
        case "gate_departure": return leg?.estimatedOut ?? leg?.scheduledOut
        case "takeoff": return leg?.estimatedOff ?? leg?.scheduledOff
        case "gate_arrival": return leg?.estimatedIn ?? leg?.scheduledIn
        default: return nil
        }
    }

    /// Backend's airport-local string verbatim; falls back to the predicted
    /// entry rendered in the client's own airport zone, then the raw leg.
    private var nextEventTimeText: String {
        if let display = phase?.nextEventLocalDisplay, !display.isEmpty { return display }
        if let entry = nextEventEntry { return entry.displayTime(fallbackZone: nextEventZone) }
        if let iso = fallbackNextEventISO { return TimeFmt.clockWithZone(iso, zone: nextEventZone) }
        return "—"
    }

    /// Minutes to the next event as of NOW, advanced from the value at
    /// source-pull time — or computed from the fallback timestamp.
    private var minutesToNextEventNow: Int? {
        if let minutes = phase?.minutesToNextEvent, let asOf {
            return minutes - Int(Date().timeIntervalSince(asOf) / 60)
        }
        if let date = TimeFmt.parseISO(nextEventEntry?.time ?? fallbackNextEventISO) {
            return Int(date.timeIntervalSinceNow / 60)
        }
        return nil
    }

    /// Minutes in the current phase as of NOW — the server's value is frozen
    /// at pull time, so rendering it verbatim would read "2 min" forever.
    private var elapsedInPhaseMinNow: Int? {
        guard let elapsed = phase?.elapsedInPhaseMin, let asOf else { return nil }
        return elapsed + Int(Date().timeIntervalSince(asOf) / 60)
    }

    /// "in 88 min" advanced to now. Past zero the prediction is simply old —
    /// name the last predicted time instead of the alarming-sounding
    /// "past predicted time" (the overdue flag has its own explicit row).
    private var countdownText: String? {
        guard let minutes = minutesToNextEventNow else { return nil }
        if minutes < 0 {
            if phase?.isOverdue == true { return nil }
            let last = nextEventTimeText
            return last == "\u{2014}" ? "awaiting update" : "awaiting update \u{2014} last predicted \(last)"
        }
        if minutes < 120 { return "in \(minutes) min" }
        let hours = Double(minutes) / 60
        return "in ~\(Int(hours.rounded()))h"
    }

    /// Server delta first, then the leg's own slip for the matching slot.
    private var deltaMinutes: Int? {
        if let delta = nextEventEntry?.delayVsScheduleMin { return delta }
        switch phase?.nextEvent {
        case "gate_departure": return leg?.departureSlipMinutes.map { Int($0.rounded()) }
        case "gate_arrival": return leg?.arrivalSlipMinutes.map { Int($0.rounded()) }
        default: return nil
        }
    }

    // MARK: - Small helpers

    private func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func phaseIcon(_ phase: BriefPhase) -> String {
        switch phase.code {
        case "TAXI_OUT", "TAXI_IN": return "milestone"
        case "AIRBORNE": return "plane"
        case "ARRIVED": return "circle-check"
        case "CANCELLED": return "circle-x"
        default: return "clock"
        }
    }

    private func phaseTone(_ phase: BriefPhase) -> ChipTone {
        switch phase.code {
        case "CANCELLED": return .alert
        case "ARRIVED": return .ok
        case "TAXI_OUT", "TAXI_IN": return .watch
        case "AIRBORNE": return .info
        default: return .neutral
        }
    }

    private func taxiLabel(_ code: String) -> String {
        switch code {
        case "NORMAL": return "Normal for this airport"
        case "ELEVATED": return "Longer than usual"
        case "EXTENDED": return "Well beyond normal"
        default: return code.capitalized
        }
    }

    private func taxiTone(_ code: String) -> ChipTone {
        switch code {
        case "EXTENDED": return .alert
        case "ELEVATED": return .watch
        case "NORMAL": return .ok
        default: return .neutral
        }
    }

    private func movementIcon(_ code: String) -> String {
        switch code {
        case "STOPPED": return "octagon-pause"
        case "TAXIING": return "move-right"
        case "TAKEOFF_ROLL": return "plane-takeoff"
        case "AIRBORNE": return "plane"
        default: return "map-pin"
        }
    }

    private func movementColor(_ code: String) -> Color {
        switch code {
        case "STOPPED": return Theme.gold
        case "TAKEOFF_ROLL", "AIRBORNE": return Theme.teal
        case "TAXIING": return Theme.green
        default: return Theme.inkSecondary
        }
    }
}
