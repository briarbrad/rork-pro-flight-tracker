import SwiftUI

/// Alerts tab: chronological feed of every fired signal across all flights.
struct AlertsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.alerts.isEmpty {
                    emptyState
                } else {
                    alertList
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Alerts")
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
            ForEach(store.alerts.sorted { $0.createdAt > $1.createdAt }) { alert in
                AlertRow(alert: alert)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Keeps the floating tab bar from covering the last alert card.
        .contentMargins(.bottom, 24, for: .scrollContent)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.green.opacity(0.12))
                    .frame(width: 96, height: 96)
                LucideIcon(name: "bell", size: 40, fallback: "bell")
                    .foregroundStyle(Theme.green)
            }
            Text("All quiet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("When any early-warning signal fires on a tracked flight — a ground stop, a late inbound, storms building — it lands here.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AlertRow: View {
    let alert: FlightAlert

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(alert.level.color.opacity(0.14))
                    .frame(width: 38, height: 38)
                LucideIcon(name: alert.icon, size: 17, fallback: "bell")
                    .foregroundStyle(alert.level.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(alert.ident)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.teal)
                    Spacer()
                    Text(TimeFmt.relative(alert.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(3)
            }

            if !alert.isRead {
                Circle()
                    .fill(Theme.teal)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .cardStyle(padding: 14)
    }
}
