import SwiftUI

/// Root tab navigation: Flights watchlist, Airports lookup, Alerts feed.
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
            Tab("Flights", systemImage: "airplane") {
                WatchlistView()
            }

            Tab("Airports", systemImage: "building.2") {
                AirportsView()
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
