import SwiftUI

/// The four trip milestones, in sequence.
enum TimelineSlot: Hashable, CaseIterable {
    case gateDeparture, takeoff, landing, gateArrival

    func label(isActual: Bool) -> String {
        switch self {
        case .gateDeparture: return isActual ? "Departed" : "Gate departure"
        case .takeoff: return isActual ? "Took off" : "Takeoff"
        case .landing: return isActual ? "Landed" : "Landing"
        case .gateArrival: return isActual ? "Arrived" : "Gate arrival"
        }
    }
}

/// THE one place flight timing renders: a connected vertical timeline of the
/// four trip milestones — gate departure, takeoff, landing, gate arrival —
/// each with its time, provenance, delay chip, and superseded schedule in a
/// single visual sequence. Replaces the old hero time columns + separate
/// Predicted Times card, which showed overlapping data twice.
///
/// Data rules (unchanged from the cards this replaces):
/// - Server-computed entries (live layer, brief fallback) win per slot and
///   are never recomputed here; the raw leg milestones fill the gaps
///   (landing has no server slot).
/// - Departure-side rows read origin-local, arrival rows destination-local.
/// - A predicted delta inside the brief's own uncertainty band with no
///   identified cause renders as neutral "≈ on time"; actual late times are
///   facts and never soften.
/// - CONTROLLED (FAA slot) keeps the solid authoritative styling.
/// - Tapping a row with a `basis` reveals how that time was computed.
struct TripTimelineView: View {
    let leg: AeroFlight?
    /// Server predicted times — live layer's on every refresh, brief's
    /// before the first live pull. Nil = leg milestones only.
    let times: BriefPredictedTimes?
    /// Truth phase — drives which marker is "next" and overdue coloring.
    let phase: BriefPhase?
    let zones: FlightZones
    var timezones: BriefTimezones? = nil
    /// Judges predicted deltas against the brief's own uncertainty band —
    /// the same instance drives chips and the inline explanation so they
    /// can never disagree.
    var explainer: DeltaExplainer? = nil

    @State private var expandedSlot: TimelineSlot?
    @State private var showFootnoteDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(milestones.enumerated()), id: \.element.slot) { index, milestone in
                    markerRow(milestone,
                              isLast: index == milestones.count - 1,
                              isNext: index == nextIndex)
                }
            }
            footnotes
        }
    }

    // MARK: - Milestone resolution

    private struct Milestone {
        let slot: TimelineSlot
        let entry: BriefPredictedTime?
        let scheduled: String?
        let estimated: String?
        let actual: String?
        let zone: TimeZone?
        let airport: String?
        let gate: String?

        /// Happened = the leg reported an actual, or the server entry says so.
        var isComplete: Bool { actual != nil || entry?.isActual == true }
    }

    private var originZone: TimeZone? {
        AirportTimeZones.named(timezones?.origin ?? times?.gateDeparture?.timezone) ?? zones.origin
    }

    private var destinationZone: TimeZone? {
        AirportTimeZones.named(timezones?.destination ?? times?.gateArrival?.timezone) ?? zones.destination
    }

    private var milestones: [Milestone] {
        [
            Milestone(slot: .gateDeparture,
                      entry: times?.gateDeparture,
                      scheduled: leg?.scheduledOut,
                      estimated: leg?.estimatedOut,
                      actual: leg?.actualOut,
                      zone: originZone,
                      airport: leg?.originDisplay,
                      gate: gateText(leg?.gateOrigin, leg?.terminalOrigin)),
            Milestone(slot: .takeoff,
                      entry: times?.takeoff,
                      scheduled: leg?.scheduledOff,
                      estimated: leg?.estimatedOff,
                      actual: leg?.actualOff,
                      zone: originZone,
                      airport: nil,
                      gate: nil),
            Milestone(slot: .landing,
                      entry: nil, // no server slot for landing — leg milestones only
                      scheduled: leg?.scheduledOn,
                      estimated: leg?.estimatedOn,
                      actual: leg?.actualOn,
                      zone: destinationZone,
                      airport: nil,
                      gate: nil),
            Milestone(slot: .gateArrival,
                      entry: times?.gateArrival,
                      scheduled: leg?.scheduledIn,
                      estimated: leg?.estimatedIn,
                      actual: leg?.actualIn,
                      zone: destinationZone,
                      airport: leg?.destDisplay,
                      gate: gateText(leg?.gateDestination, leg?.terminalDestination)),
        ]
    }

    /// The first milestone that hasn't happened — the highlighted "you are
    /// here" marker. None once the flight is over or cancelled.
    private var nextIndex: Int? {
        guard phase?.isCancelled != true, phase?.isOver != true else { return nil }
        return milestones.firstIndex { !$0.isComplete }
    }

    // MARK: - Rows

    @ViewBuilder
    private func markerRow(_ milestone: Milestone, isLast: Bool, isNext: Bool) -> some View {
        let hasBasis = milestone.entry?.basis != nil
        HStack(alignment: .top, spacing: 12) {
            indicatorColumn(isComplete: milestone.isComplete, isNext: isNext, isLast: isLast)
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    guard hasBasis else { return }
                    Haptics.tap()
                    withAnimation(.snappy) {
                        expandedSlot = expandedSlot == milestone.slot ? nil : milestone.slot
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        metaLine(milestone)
                        timeLine(milestone, hasBasis: hasBasis)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!hasBasis)

                supersededScheduleLine(milestone)
                crossesDayLine(milestone)
                if milestone.slot == .takeoff { progressLine }

                if expandedSlot == milestone.slot, let basis = milestone.entry?.basis {
                    basisReveal(slot: milestone.slot, basis: basis)
                }
            }
            .padding(.bottom, isLast ? 0 : Space.sm)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "GATE DEPARTURE · SEA · T2 Gate B7" + FAA-controlled chip.
    private func metaLine(_ milestone: Milestone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(metaText(milestone))
                .font(TypeScale.caption2Strong)
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if milestone.entry?.isControlled == true {
                StatusChip(text: "FAA-controlled", tone: .watch, size: .mini,
                           uppercased: true)
            }
        }
    }

    private func metaText(_ milestone: Milestone) -> String {
        var parts: [String] = [milestone.slot.label(isActual: milestone.isComplete)]
        if let airport = milestone.airport, airport != "???" { parts.append(airport) }
        if let gate = milestone.gate { parts.append(gate) }
        return parts.joined(separator: " · ")
    }

    /// The time itself + delta chip + basis chevron. Never shrinks — long
    /// strings wrap under themselves rather than scaling down.
    @ViewBuilder
    private func timeLine(_ milestone: Milestone, hasBasis: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if milestone.entry?.isControlled == true {
                // FAA-authoritative fact — the ONLY solid-chip style besides
                // the EDCT banner.
                HStack(spacing: 6) {
                    StatusChip(text: milestone.entry?.displayTime(fallbackZone: milestone.zone) ?? "—",
                               tone: .info, size: .mini, style: .solid)
                    Text("FAA slot")
                        .font(TypeScale.kicker)
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(Theme.tealDeep)
                }
            } else {
                Text(timeText(milestone))
                    .font(TypeScale.time)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: timeText(milestone))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(timeColor(milestone))
            }
            deltaChip(milestone)
            if hasBasis {
                LucideIcon(name: expandedSlot == milestone.slot ? "chevron-up" : "chevron-down",
                           size: 10, fallback: "chevron.down")
                    .foregroundStyle(Theme.hairline)
            }
        }
    }

    private func timeText(_ milestone: Milestone) -> String {
        if let entry = milestone.entry, !entry.isUnknown {
            return entry.displayTime(fallbackZone: milestone.zone)
        }
        if let iso = milestone.actual ?? milestone.estimated ?? milestone.scheduled {
            return TimeFmt.clockWithZone(iso, zone: milestone.zone)
        }
        return "—"
    }

    private func timeColor(_ milestone: Milestone) -> Color {
        if milestone.entry?.isUnknown == true { return Theme.inkSecondary }
        if milestone.entry == nil && milestone.actual == nil
            && milestone.estimated == nil && milestone.scheduled == nil {
            return Theme.inkSecondary
        }
        // Schedule-only value = nothing fresher known yet — muted.
        if milestone.entry?.isScheduledOnly == true
            || (milestone.entry == nil && milestone.actual == nil && milestone.estimated == nil) {
            return Theme.inkSecondary
        }
        return Theme.ink
    }

    /// Delta vs schedule. Server delta wins; leg slip fills the gaps
    /// (landing). Actual times are facts: the reassuring green "on time" is
    /// for predictions only, and a late actual is never softened to noise.
    @ViewBuilder
    private func deltaChip(_ milestone: Milestone) -> some View {
        if let delay = delta(milestone), milestone.entry?.isUnknown != true,
           !(milestone.isComplete && delay <= 0) {
            let late = delay > 0
            if late, !milestone.isComplete,
               explainer?.significance(of: delay) == DeltaSignificance.noise {
                StatusChip(text: "≈ on time", tone: .neutral, size: .mini)
            } else {
                let tone: ChipTone = late
                    ? (SlipSeverity.of(minutes: Double(delay)) == .alert ? .alert : .watch)
                    : .ok
                StatusChip(text: late ? "+\(delay) min" : "on time", tone: tone, size: .mini)
            }
        }
    }

    private func delta(_ milestone: Milestone) -> Int? {
        if let serverDelta = milestone.entry?.delayVsScheduleMin { return serverDelta }
        return TimeFmt.slipMinutes(scheduled: milestone.scheduled,
                                   actual: milestone.actual,
                                   estimated: milestone.estimated)
            .map { Int($0.rounded()) }
    }

    /// "Sched 10:15 AM" struck through when the shown time superseded it.
    @ViewBuilder
    private func supersededScheduleLine(_ milestone: Milestone) -> some View {
        let effective = milestone.actual ?? milestone.estimated ?? milestone.entry?.time
        if let effective, let sched = milestone.scheduled,
           TimeFmt.parseISO(effective) != TimeFmt.parseISO(sched) {
            Text("Sched \(TimeFmt.clock(sched, zone: milestone.zone))")
                .font(TypeScale.caption2)
                .monospacedDigit()
                .strikethrough()
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// An event on a different local day than the departure is a fact worth
    /// stating outright — the overnight-arrival case.
    @ViewBuilder
    private func crossesDayLine(_ milestone: Milestone) -> some View {
        let departureRef = leg?.actualOut ?? leg?.estimatedOut ?? leg?.scheduledOut
        let shown = milestone.actual ?? milestone.estimated ?? milestone.entry?.time ?? milestone.scheduled
        if shown != departureRef,
           TimeFmt.crossesLocalDay(shown, zone: milestone.zone,
                                   reference: departureRef, referenceZone: originZone),
           let dayLabel = TimeFmt.weekdayDate(shown, zone: milestone.zone) {
            Text(dayLabel)
                .font(TypeScale.caption2Medium)
                .foregroundStyle(Theme.teal)
        }
    }

    /// Route progress on the airborne segment (was the hero's middle column).
    @ViewBuilder
    private var progressLine: some View {
        if phase?.isEnRoute == true, let progress = leg?.progressPercent, progress > 0 {
            HStack(spacing: 5) {
                LucideIcon(name: "plane", size: 11, fallback: "airplane")
                Text(progressText(progress))
                    .font(TypeScale.caption2Strong)
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.teal)
        }
    }

    private func progressText(_ progress: Double) -> String {
        var text = "\(Int(progress))% of route flown"
        if let tail = leg?.registration { text += " · \(tail)" }
        return text
    }

    private func basisReveal(slot: TimelineSlot, basis: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(slot.label(isActual: false)) — how this was computed")
                .font(TypeScale.kicker)
                .foregroundStyle(Theme.ink)
            GlossaryText(text: basis, font: .caption2, color: Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: Theme.Radius.well))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Indicator (dot + connecting segment)

    private func indicatorColumn(isComplete: Bool, isNext: Bool, isLast: Bool) -> some View {
        VStack(spacing: 3) {
            dot(isComplete: isComplete, isNext: isNext)
            if !isLast {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isComplete ? Theme.teal : Theme.hairline)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 16)
        .padding(.top, 1)
    }

    @ViewBuilder
    private func dot(isComplete: Bool, isNext: Bool) -> some View {
        if isComplete {
            ZStack {
                Circle().fill(Theme.teal)
                LucideIcon(name: "check", size: 8, fallback: "checkmark")
                    .foregroundStyle(.white)
            }
            .frame(width: 15, height: 15)
        } else if isNext {
            let color = phase?.isOverdue == true ? Theme.red : Theme.teal
            ZStack {
                Circle().stroke(color, lineWidth: 2)
                Circle().fill(color).frame(width: 6, height: 6)
            }
            .frame(width: 15, height: 15)
        } else {
            Circle()
                .stroke(Theme.hairline, lineWidth: 2)
                .frame(width: 13, height: 13)
                .frame(width: 15, height: 15)
        }
    }

    // MARK: - Footnotes (absorbed from the old Predicted Times card)

    /// Only the decision-relevant line stays always-visible: the delay
    /// explanation. The timezone note and horizon caveat are reference
    /// context — collapsed behind "Details" (the same disclosure pattern as
    /// "More context") so the card reads calm, not busy.
    @ViewBuilder
    private var footnotes: some View {
        // Any late delta gets its one-line why RIGHT HERE — the user should
        // never have to scroll to the narrative to learn whether a +4 min
        // chip has a cause or is just schedule noise.
        if let times, let explanation = explainer?.explanationLine(for: times) {
            HStack(alignment: .top, spacing: 5) {
                LucideIcon(name: "circle-help", size: 10, fallback: "questionmark.circle")
                    .padding(.top, 1)
                Text(explanation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(TypeScale.caption2)
            .foregroundStyle(Theme.inkSecondary)
        }

        if zoneCaption != nil || times?.uncertaintyNote != nil {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { showFootnoteDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Details")
                        .font(TypeScale.caption2Strong)
                    LucideIcon(name: showFootnoteDetails ? "chevron-up" : "chevron-down",
                               size: 11, fallback: "chevron.down")
                }
                .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(.plain)

            if showFootnoteDetails {
                footnoteDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var footnoteDetails: some View {
        if let zoneCaption {
            HStack(spacing: 5) {
                LucideIcon(name: "globe", size: 10, fallback: "globe")
                Text(zoneCaption)
            }
            .font(TypeScale.caption2)
            .foregroundStyle(Theme.inkSecondary)
        }

        if let note = times?.uncertaintyNote {
            Text(note)
                .font(TypeScale.caption2)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    // MARK: - Helpers

    private func gateText(_ gate: String?, _ terminal: String?) -> String? {
        switch (gate, terminal) {
        case let (gate?, terminal?): return "T\(terminal) · Gate \(gate)"
        case let (gate?, nil): return "Gate \(gate)"
        case let (nil, terminal?): return "Terminal \(terminal)"
        default: return nil
        }
    }
}
