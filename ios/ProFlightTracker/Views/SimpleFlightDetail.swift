import SwiftUI

/// Simple-mode prediction card — the answer at the top of the flight screen.
/// Prefers backend `simple_summary`; otherwise composes from the same
/// verdict / times / narrative the Pro layout already has.
struct SimplePredictionCard: View {
    let prediction: SimplePrediction
    var asOf: Date? = nil
    var isStale: Bool = false
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Based on what I know")
                .font(TypeScale.kicker)
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.teal)

            Text("Here's what I think will happen")
                .font(TypeScale.headline)
                .foregroundStyle(Theme.ink)

            Text(prediction.headline)
                .font(TypeScale.bodyStrong)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(prediction.body)
                .font(TypeScale.body)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = prediction.confidenceNote, !note.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    LucideIcon(name: "info", size: 12, fallback: "info.circle")
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 1)
                    Text(note)
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let asOf {
                FreshnessCaption(asOf: asOf, isStale: isStale,
                                 staleHint: "refresh for the current picture.",
                                 onAction: onRefresh)
            }
        }
        .cardStyle()
    }
}

/// Gate / Takeoff / Arrival — the three times a traveller actually wants.
/// Server `local_display` wins; the client's airport zone fills gaps.
struct SimpleTimesCard: View {
    let times: BriefPredictedTimes?
    let leg: AeroFlight?
    let zones: FlightZones

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(icon: "clock", title: "Times")

            HStack(alignment: .top, spacing: Space.xs) {
                timeColumn(title: "Gate",
                           entry: times?.gateDeparture,
                           iso: leg?.actualOut ?? leg?.estimatedOut ?? leg?.scheduledOut,
                           zone: zones.origin,
                           caption: gateCaption(leg?.gateOrigin, leg?.terminalOrigin))
                timeColumn(title: "Takeoff",
                           entry: times?.takeoff,
                           iso: leg?.actualOff ?? leg?.estimatedOff ?? leg?.scheduledOff,
                           zone: zones.origin,
                           caption: nil)
                timeColumn(title: "Arrival",
                           entry: times?.gateArrival,
                           iso: leg?.actualIn ?? leg?.estimatedIn ?? leg?.scheduledIn,
                           zone: zones.destination,
                           caption: gateCaption(leg?.gateDestination, leg?.terminalDestination))
            }

            if let caption = zoneCaption {
                HStack(spacing: 5) {
                    LucideIcon(name: "globe", size: 10, fallback: "globe")
                    Text(caption)
                }
                .font(TypeScale.caption2)
                .foregroundStyle(Theme.inkSecondary)
            }
        }
        .cardStyle()
    }

    private func timeColumn(title: String,
                            entry: BriefPredictedTime?,
                            iso: String?,
                            zone: TimeZone?,
                            caption: String?) -> some View {
        let text: String = {
            if let entry, !entry.isUnknown {
                return entry.displayTime(fallbackZone: zone)
            }
            if iso != nil { return TimeFmt.clockWithZone(iso, zone: zone) }
            return "—"
        }()
        let delay = entry?.delayVsScheduleMin

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TypeScale.kicker)
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.inkSecondary)
            Text(text)
                .font(TypeScale.time)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let delay, delay > 0 {
                Text("+\(delay) min")
                    .font(TypeScale.caption2Strong)
                    .foregroundStyle(SlipSeverity.of(minutes: Double(delay)).textColor(default: Theme.goldText))
            } else if let caption {
                Text(caption)
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.sm)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: Theme.Radius.well))
    }

    private func gateCaption(_ gate: String?, _ terminal: String?) -> String? {
        switch (gate, terminal) {
        case let (gate?, terminal?): return "T\(terminal) · \(gate)"
        case let (gate?, nil): return "Gate \(gate)"
        case let (nil, terminal?): return "T\(terminal)"
        default: return nil
        }
    }

    private var zoneCaption: String? {
        let origin = AirportTimeZones.cityName(zones.origin)
        let dest = AirportTimeZones.cityName(zones.destination)
        switch (origin, dest) {
        case let (origin?, dest?) where origin != dest:
            return "Gate and takeoff in \(origin) time · arrival in \(dest) time"
        case let (origin?, _):
            return "Local time at \(origin)"
        default:
            return nil
        }
    }
}

/// One risk / confidence line. LOW/LOW and status-only LOW stay neutral —
/// never the reassuring green "on time".
struct SimpleRiskCard: View {
    let treatment: SimpleRiskTreatment

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            StatusChip(text: treatment.label,
                       icon: treatment.icon,
                       tone: treatment.chipTone)
            Text(treatment.detail)
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}

/// Assigned takeoff without the EDCT / wheels-up jargon the Pro banner uses.
struct SimpleAssignedTakeoffNotice: View {
    let edct: BriefEdct
    var originZone: TimeZone? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            LucideIcon(name: "clock", size: 16, fallback: "clock")
                .foregroundStyle(Theme.gold)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Assigned takeoff")
                    .font(TypeScale.captionBold)
                    .foregroundStyle(Theme.ink)
                Text(edct.displayTime(fallbackZone: originZone))
                    .font(TypeScale.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text("The FAA has given this flight a takeoff time.")
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}
