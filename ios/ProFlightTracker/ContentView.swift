import SwiftUI

/// Root tab navigation: Trips watchlist and Alerts feed. Airport lookup is
/// reached from the Trips toolbar (sheet), not a tab of its own.
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // The floating tab bar covers card content at the bottom of scroll
        // views — minimize it on scroll-down so long pages stay readable.
        if #available(iOS 26.0, *) {
            tabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView {
            Tab("Trips", systemImage: "airplane") {
                WatchlistView()
            }

            Tab("Alerts", systemImage: "bell") {
                AlertsView()
            }
            .badge(store.unreadAlertCount)
        }
        .tint(Theme.teal)
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
}
