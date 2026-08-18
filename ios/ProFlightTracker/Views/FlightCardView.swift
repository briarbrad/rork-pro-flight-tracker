import SwiftUI

/// Watchlist card: route, times, status, gate, brief verdict badge (the only
/// flight-level verdict), and a live-signal count chip.
struct FlightCardView: View {
    let flight: TrackedFlight
    let snapshot: FlightSnapshot?
    let isRefreshing: Bool
    /// Per-card retry for a failed refresh — fired from the error strip so a
    /// single flight can be retried without a global pull-to-refresh.
    var onRetry: (() -> Void)? = nil

    private var refreshError: String? {
        isRefreshing ? nil : snapshot?.refreshError
    }

    private var leg: AeroFlight? { snapshot?.flight }
    /// Stale = older than the server-declared refresh window. Signalled by a
    /// badge plus a muted card tint — never by dimming the card's text.
    private var isStale: Bool { snapshot?.autoRefreshDue == true && !isRefreshing }
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
                } else if refreshError != nil {
                    StatusChip(text: "Needs refresh", icon: "triangle-alert",
                               tone: .from(.high), size: .mini, uppercased: true)
                } else if isStale {
                    StatusChip(text: "Stale", icon: "history", tone: .watch,
                               size: .mini, uppercased: true)
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

            // A failed background refresh must be visible, not silent: red
            // strip with the reason and an in-place retry for THIS flight.
            if let refreshError {
                HStack(spacing: 8) {
                    LucideIcon(name: "triangle-alert", size: 13,
                               fallback: "exclamationmark.triangle")
                    Text(refreshError)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let onRetry {
                        Button {
                            Haptics.tap()
                            onRetry()
                        } label: {
                            HStack(spacing: 4) {
                                LucideIcon(name: "refresh-cw", size: 11,
                                           fallback: "arrow.clockwise")
                                Text("Retry")
                                    .font(.caption.weight(.bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.red.opacity(0.12))
                            .clipShape(.capsule)
                        }
                        // Borderless so the retry tap doesn't trigger the
                        // row's NavigationLink.
                        .buttonStyle(.borderless)
                    }
                }
                .foregroundStyle(Theme.red)
                .padding(10)
                .background(Theme.red.opacity(0.07))
                .clipShape(.rect(cornerRadius: Theme.Radius.well))
            }

            // Same freshness language as the flight screen — amber once the
            // data is older than its server-declared refresh window.
            if let refreshed = snapshot?.lastRefreshed {
                FreshnessCaption(asOf: refreshed,
                                 prefix: "updated",
                                 isStale: isStale)
            }
        }
        .padding(16)
        .background(isStale ? Theme.staleSurface : Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            if isStale {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1)
            }
        }
        .cardShadow()
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
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var departureSlip: SlipSeverity {
        SlipSeverity.of(minutes: leg?.departureSlipMinutes)
    }
}
