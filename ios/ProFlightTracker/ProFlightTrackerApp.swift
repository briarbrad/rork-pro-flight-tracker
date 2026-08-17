//
//  ProFlightTrackerApp.swift
//  ProFlightTracker
//

import SwiftUI

@main
struct ProFlightTrackerApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
