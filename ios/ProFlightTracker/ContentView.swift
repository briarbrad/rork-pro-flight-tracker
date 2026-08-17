import SwiftUI

/// Root tab navigation: Flights watchlist, Airports lookup, Alerts feed.
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
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
