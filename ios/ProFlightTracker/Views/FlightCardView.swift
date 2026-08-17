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
        FlightZones.resolve(flight: leg, brief: snapshot?.brief?.timezones)
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
                // Verdicts come exclusively from /api/brief — no brief, no badge.
                if let brief = snapshot?.brief {
                    BriefVerdictBadge(brief: brief)
                }
            }

            routeRow

            HStack(spacing: 8) {
                statusChip
                if let gate = leg?.gateOrigin {
                    infoChip(icon: "door-open", text: "Gate \(gate)")
                }
                if let signals = assessment?.signals, !signals.isEmpty {
                    infoChip(icon: "activity",
                             text: "\(signals.count) signal\(signals.count == 1 ? "" : "s")",
                             tint: assessment?.level.color)
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
                         tint: departureSlipped ? Theme.gold : Theme.inkSecondary,
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

    private var departureSlipped: Bool {
        (leg?.departureSlipMinutes ?? 0) >= 15
    }

    private var statusChip: some View {
        infoChip(icon: "radio", text: leg?.status ?? "Awaiting data", tint: Theme.teal)
    }

    private func infoChip(icon: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            LucideIcon(name: icon, size: 11, fallback: "circle.fill")
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint ?? Theme.inkSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((tint ?? Theme.inkSecondary).opacity(0.1))
        .clipShape(.capsule)
    }
}
