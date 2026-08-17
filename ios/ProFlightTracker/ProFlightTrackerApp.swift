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
                // The design system is fixed light (white cards on a warm
                // canvas) — lock the scheme so system chrome can't go dark
                // against it. Stopgap until a real dark palette exists.
                .preferredColorScheme(.light)
        }
    }
}
