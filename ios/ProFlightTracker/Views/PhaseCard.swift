import SwiftUI

/// The flight's current lifecycle state, rendered as the top card of the
/// brief once the aircraft is out of the gate. The headline is always the
/// NEXT event — "Takeoff 10:28 PM EDT, in 88 min" — never the schedule: a
/// flight 100 minutes into a taxi hold doesn't care that pushback was early.
struct PhaseCard: View {
    let brief: StoredBrief
    let zones: FlightZones
    /// Re-run affordance for the stale treatment — briefs stay user-initiated.
    var onRerun: (() -> Void)? = nil

    private var phase: BriefPhase? { brief.phase }

    var body: some View {
        if let phase {
            VStack(alignment: .leading, spacing: 12) {
                phaseHeader(phase)

                if phase.isCancelled {
                    cancelledRow(phase)
                } else if !phase.isOver {
                    nextEventBlock(phase)
                }

                // Taxi assessment — whether this wait is abnormal for THIS
                // airport. Summary is server-written, rendered verbatim.
                if let taxi = brief.taxi, taxi.isApplicable {
                    taxiBlock(taxi)
                }

                // Live position — only when something is actually reported.
                // Patchy surface ADS-B is missing data, not a problem with
                // the flight, so absence renders as nothing.
                if let position = brief.position, position.isAvailable {
                    positionRow(position)
                }

                // Same stale treatment as the verdict card: this card
                // described the flight as of brief-run time.
                if brief.isStale {
                    staleFooter
                }
            }
            .opacity(brief.isStale ? 0.75 : 1)
            .cardStyle()
        }
    }

    private var staleFooter: some View {
        Button {
            Haptics.tap()
            onRerun?()
        } label: {
            HStack(spacing: 6) {
                LucideIcon(name: "history", size: 11, fallback: "clock")
                Text("As of \(TimeFmt.relative(brief.runAt)) — re-run the brief for the live picture.")
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.gold.opacity(0.1))
            .clipShape(.rect(cornerRadius: 10))
        }
    }

    // MARK: - Phase header

    private func phaseHeader(_ phase: BriefPhase) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                LucideIcon(name: phaseIcon(phase), size: 13, fallback: "airplane")
                Text(phase.phaseLabel ?? phase.code.capitalized)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(phaseColor(phase))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(phaseColor(phase).opacity(0.12))
            .clipShape(.capsule)

            Spacer()

            // Advances with wall-clock time — the server's value is frozen at
            // brief-run time and would read "In phase 2 min" forever.
            if let elapsed = brief.elapsedInPhaseMinNow, phase.isEnRoute {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("In phase")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(durationText(elapsed))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    // MARK: - Next event headline

    private func nextEventBlock(_ phase: BriefPhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(phase.nextEventLabel ?? "Next event")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .textCase(.uppercase)
                if phase.isControlled {
                    // FAA-assigned time — materially harder than an estimate.
                    Text("FAA-CONTROLLED")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.gold.opacity(0.14))
                        .clipShape(.capsule)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(nextEventTimeText(phase))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(phase.isOverdue ? Theme.red : Theme.ink)
                if let countdown = countdownText(phase) {
                    Text(countdown)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(phase.isOverdue ? Theme.red : Theme.teal)
                }
            }

            if phase.isOverdue {
                HStack(spacing: 6) {
                    LucideIcon(name: "trending-down", size: 12, fallback: "arrow.down.right")
                    Text("Overdue — the predicted time has passed and it hasn't happened yet.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.red)
            }

            if let basis = phase.nextEventBasis, !basis.isEmpty {
                Text("Basis: \(basis)")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func cancelledRow(_ phase: BriefPhase) -> some View {
        HStack(spacing: 8) {
            LucideIcon(name: "circle-x", size: 14, fallback: "xmark.circle")
            Text(phase.phaseDetail ?? "This flight has been cancelled.")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.red)
    }

    // MARK: - Taxi assessment

    private func taxiBlock(_ taxi: BriefTaxi) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(taxiLabel(taxi.assessmentCode))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(taxiColor(taxi.assessmentCode))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(taxiColor(taxi.assessmentCode).opacity(0.13))
                    .clipShape(.capsule)
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
        .background(taxiColor(taxi.assessmentCode).opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
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

    // MARK: - Helpers

    /// Backend's airport-local string verbatim; falls back to the full
    /// predicted-times entry rendered in the client's own airport zone.
    private func nextEventTimeText(_ phase: BriefPhase) -> String {
        if let display = phase.nextEventLocalDisplay, !display.isEmpty { return display }
        if let entry = brief.nextEventPredictedTime {
            let zone = phase.nextEvent == "gate_arrival" ? zones.destination : zones.origin
            return entry.displayTime(fallbackZone: zone)
        }
        return "—"
    }

    /// "in 88 min" advanced to now. Past zero the prediction is simply old —
    /// name the last predicted time instead of the alarming-sounding
    /// "past predicted time" (the overdue flag has its own explicit row).
    private func countdownText(_ phase: BriefPhase) -> String? {
        guard let minutes = brief.minutesToNextEventNow else { return nil }
        if minutes < 0 {
            if phase.isOverdue { return nil }
            let last = nextEventTimeText(phase)
            return last == "\u{2014}" ? "awaiting update" : "awaiting update \u{2014} last predicted \(last)"
        }
        if minutes < 120 { return "in \(minutes) min" }
        let hours = Double(minutes) / 60
        return "in ~\(Int(hours.rounded()))h"
    }

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

    private func phaseColor(_ phase: BriefPhase) -> Color {
        switch phase.code {
        case "CANCELLED": return Theme.red
        case "ARRIVED": return Theme.green
        case "TAXI_OUT", "TAXI_IN": return Theme.gold
        case "AIRBORNE": return Theme.teal
        default: return Theme.inkSecondary
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

    private func taxiColor(_ code: String) -> Color {
        switch code {
        case "EXTENDED": return Theme.red
        case "ELEVATED": return Theme.gold
        case "NORMAL": return Theme.green
        default: return Theme.inkSecondary
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
