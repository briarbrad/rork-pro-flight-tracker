import SwiftUI

/// Alerts tab: chronological feed of every fired signal across all flights.
/// Rows deep-link into the flight they're about and carry route + phase +
/// "what changed" context; opening one marks it read.
struct AlertsView: View {
    @Environment(AppStore.self) private var store
    @State private var path: [TrackedFlight] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.alerts.isEmpty {
                    emptyState
                } else {
                    alertList
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Alerts")
            .navigationDestination(for: TrackedFlight.self) { flight in
                FlightDetailView(flight: flight)
            }
            .toolbar {
                if store.unreadAlertCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") {
                            Haptics.tap()
                            store.markAllAlertsRead()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.teal)
                    }
                }
            }
        }
    }

    private var alertList: some View {
        List {
            ForEach(store.alerts.sorted { $0.updatedAt > $1.updatedAt }) { alert in
                Button {
                    open(alert)
                } label: {
                    AlertRow(alert: alert,
                             isFlightTracked: store.trackedFlight(forKey: alert.flightKey) != nil)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 5, leading: Space.md, bottom: 5, trailing: Space.md))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Keeps the floating tab bar from covering the last alert card.
        .contentMargins(.bottom, Space.lg, for: .scrollContent)
    }

    /// Opening an alert marks it read; if its flight is still on the
    /// watchlist, deep-link straight to that flight's detail screen.
    private func open(_ alert: FlightAlert) {
        Haptics.tap()
        store.markAlertRead(alert)
        if let flight = store.trackedFlight(forKey: alert.flightKey) {
            path.append(flight)
        }
    }

    private var emptyState: some View {
        EmptyState(icon: "bell",
                   iconFallback: "bell",
                   tint: Theme.green,
                   title: "All quiet",
                   message: "When any early-warning signal fires on a tracked flight — a ground stop, a late inbound, storms building — it lands here.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AlertRow: View {
    let alert: FlightAlert
    let isFlightTracked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(alert.level.color.opacity(0.14))
                    .frame(width: 38, height: 38)
                LucideIcon(name: alert.icon, size: 17, fallback: "bell")
                    .foregroundStyle(alert.level.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(alert.ident)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.teal)
                    if let route = alert.route {
                        Text(route)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(timeLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Text(alert.title)
                    .font(.subheadline.weight(alert.isRead ? .medium : .bold))
                    .foregroundStyle(Theme.ink)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(3)

                // Phase + what-changed context chips.
                HStack(spacing: 6) {
                    if let phase = alert.phaseLabel {
                        StatusChip(text: phase, icon: "plane", tone: .info, size: .mini)
                    }
                    if let note = alert.changeNote {
                        StatusChip(text: note, icon: "git-commit-horizontal",
                                   tone: .neutral, size: .mini)
                    }
                    Spacer()
                    if isFlightTracked {
                        LucideIcon(name: "chevron-right", size: 12, fallback: "chevron.right")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .padding(.top, 1)
            }

            if !alert.isRead {
                Circle()
                    .fill(Theme.teal)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .cardStyle(padding: 14)
        .contentShape(.rect)
    }

    /// Deduped alerts show when the underlying event last CHANGED, not when
    /// it first fired.
    private var timeLabel: String {
        alert.wasUpdated
            ? "updated \(TimeFmt.relative(alert.updatedAt))"
            : TimeFmt.relative(alert.createdAt)
    }
}
