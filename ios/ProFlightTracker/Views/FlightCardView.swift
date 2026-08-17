import SwiftUI

/// Watchlist card: route, times, status, gate, brief verdict badge (the only
/// flight-level verdict), and a live-signal count chip.
struct FlightCardView: View {
    let flight: TrackedFlight
    let snapshot: FlightSnapshot?
    let isRefreshing: Bool

    private var leg: AeroFlight? { snapshot?.flight }
    private var assessment: RiskAssessment? { snapshot?.assessment }
    /// Departure time in the origin's zone, arrival in the destination's.
    private var zones: FlightZones {
        FlightZones.resolve(flight: leg,
                            brief: snapshot?.live?.timezones ?? snapshot?.brief?.timezones)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flight.ident)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small).tint(Theme.teal)
                }
                // Brief verdict while fresh; the live status_only verdict
                // escalates over it and governs once the brief goes stale.
                FlightVerdictBadge(brief: snapshot?.brief, live: snapshot?.live)
            }

            routeRow

            HStack(spacing: 8) {
                StatusChip(text: leg?.status ?? "Awaiting data", icon: "radio",
                           tone: .info, size: .mini)
                if let gate = leg?.gateOrigin {
                    StatusChip(text: "Gate \(gate)", icon: "door-open",
                               tone: .neutral, size: .mini)
                }
                if let signals = assessment?.signals, !signals.isEmpty {
                    StatusChip(text: "\(signals.count) signal\(signals.count == 1 ? "" : "s")",
                               icon: "activity",
                               tone: assessment.map { ChipTone.from($0.level) } ?? .neutral,
                               size: .mini)
                }
                Spacer()
            }
        }
        .cardStyle()
    }

    private var dateLabel: String {
        if let date = TimeFmt.parseISO(leg?.scheduledOut) {
            return TimeFmt.shortDate(date)
        }
        return flight.date
    }

    private var routeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(leg?.originDisplay ?? "—")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.ink)
                timeText(leg?.estimatedOut ?? leg?.scheduledOut,
                         zone: zones.origin,
                         tint: departureSlip.textColor(default: Theme.inkSecondary),
                         alignment: .leading)
            }

            VStack(spacing: 3) {
                LucideIcon(name: "plane", size: 16, fallback: "airplane")
                    .foregroundStyle(Theme.teal)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1.5)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 2) {
                Text(leg?.destDisplay ?? "—")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.ink)
                timeText(leg?.estimatedIn ?? leg?.scheduledIn,
                         zone: zones.destination,
                         tint: Theme.inkSecondary,
                         alignment: .trailing)
            }
        }
    }

    private func timeText(_ iso: String?, zone: TimeZone?, tint: Color,
                         alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(TimeFmt.clock(iso, zone: zone))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(tint)
            if let label = TimeFmt.zoneLabel(zone, atISO: iso), iso != nil {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.8))
            }
        }
    }

    private var departureSlip: SlipSeverity {
        SlipSeverity.of(minutes: leg?.departureSlipMinutes)
    }
}
