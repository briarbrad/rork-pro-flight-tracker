import SwiftUI

/// Compact closure card for a finished flight: one factual line — when it
/// arrived, how that compared to schedule, and the gate ("Arrived 8:43 AM ·
/// 12 min early · Gate B7E"). A cancelled flight gets the red treatment.
/// Predictions are suppressed entirely once a flight is over: history is
/// never restated as prediction.
struct FlightClosureCard: View {
    let leg: AeroFlight?
    let phase: BriefPhase?
    let zones: FlightZones
    var lastRefreshed: Date? = nil

    private var isCancelled: Bool {
        phase?.isCancelled == true || leg?.cancelled == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill((isCancelled ? Theme.red : Theme.green).opacity(0.13))
                        .frame(width: 44, height: 44)
                    LucideIcon(name: isCancelled ? "circle-x" : "circle-check", size: 22,
                               fallback: isCancelled ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(isCancelled ? Theme.red : Theme.green)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(leg?.originCity ?? leg?.originDisplay ?? "—") → \(leg?.destCity ?? leg?.destDisplay ?? "—")")
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(headline)
                        .font(TypeScale.title)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    if let subline {
                        Text(subline)
                            .font(TypeScale.bodyStrong)
                            .foregroundStyle(sublineColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The airline's raw string is a footnote, never a headline.
                    if let status = leg?.status, !status.isEmpty {
                        Text("Airline status · \(status)")
                            .font(TypeScale.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let lastRefreshed {
                FreshnessCaption(asOf: lastRefreshed)
            }
        }
        .cardStyle()
    }

    private var headline: String {
        if isCancelled { return "Cancelled" }
        let arrival = leg?.actualIn ?? leg?.actualOn ?? leg?.estimatedIn
        return "Arrived \(TimeFmt.clockWithZone(arrival, zone: zones.destination))"
    }

    private var subline: String? {
        if isCancelled {
            return phase?.phaseDetail ?? "This flight has been cancelled."
        }
        var parts: [String] = []
        if let delta = arrivalDeltaText { parts.append(delta) }
        if let gate = gateText { parts.append(gate) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var sublineColor: Color {
        if isCancelled { return Theme.red }
        guard let slip = leg?.arrivalSlipMinutes else { return Theme.inkSecondary }
        if slip <= 0 { return Theme.greenText }
        return SlipSeverity.of(minutes: slip).textColor(default: Theme.inkSecondary)
    }

    private var arrivalDeltaText: String? {
        guard let slip = leg?.arrivalSlipMinutes else { return nil }
        let minutes = Int(slip.rounded())
        if minutes <= -1 { return "\(-minutes) min early" }
        if minutes >= 1 { return "\(minutes) min late" }
        return "on time"
    }

    private var gateText: String? {
        switch (leg?.gateDestination, leg?.terminalDestination) {
        case let (gate?, terminal?): return "T\(terminal) · Gate \(gate)"
        case let (gate?, nil): return "Gate \(gate)"
        case let (nil, terminal?): return "Terminal \(terminal)"
        default: return nil
        }
    }
}

/// The factual flight record for a finished flight: every reported actual
/// milestone, each in its owning airport's zone. Facts only — no predictions.
struct FlightRecordCard: View {
    let leg: AeroFlight?
    let zones: FlightZones
    /// Embedded = rendered inside a CollapsibleSection's card: keeps the
    /// "Actual times" sub-header but drops the card shell.
    var embedded: Bool = false

    private var milestones: [(label: String, icon: String, iso: String?, zone: TimeZone?)] {
        [("Left the gate", "door-open", leg?.actualOut, zones.origin),
         ("Took off", "plane-takeoff", leg?.actualOff, zones.origin),
         ("Landed", "plane-landing", leg?.actualOn, zones.destination),
         ("At the gate", "circle-check", leg?.actualIn, zones.destination)]
    }

    var body: some View {
        if embedded {
            recordContent
        } else {
            recordContent
                .cardStyle()
        }
    }

    private var recordContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "archive", title: "Actual times")

            if milestones.allSatisfy({ $0.iso == nil }) {
                Text("No actual times were reported for this flight.")
                    .font(TypeScale.caption)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                ForEach(milestones.filter { $0.iso != nil }, id: \.label) { milestone in
                    HStack(spacing: 10) {
                        LucideIcon(name: milestone.icon, size: 14, fallback: "circle")
                            .foregroundStyle(Theme.teal)
                            .frame(width: 18)
                        Text(milestone.label)
                            .font(TypeScale.captionStrong)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(TimeFmt.clockWithZone(milestone.iso, zone: milestone.zone))
                            .font(TypeScale.captionStrong)
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                // Makes the two-zone rule explicit for the record too.
                if let caption = zoneCaption {
                    HStack(spacing: 5) {
                        LucideIcon(name: "globe", size: 10, fallback: "globe")
                        Text(caption)
                    }
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private var zoneCaption: String? {
        let origin = AirportTimeZones.cityName(zones.origin)
        let dest = AirportTimeZones.cityName(zones.destination)
        switch (origin, dest) {
        case let (origin?, dest?) where origin != dest:
            return "Departure times in \(origin) time · arrival in \(dest) time"
        case let (origin?, _):
            return "Local time at \(origin)"
        default:
            return nil
        }
    }
}
