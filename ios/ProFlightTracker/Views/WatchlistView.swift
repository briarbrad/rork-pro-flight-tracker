import SwiftUI

/// Home tab: tracked flights sorted by departure, pull to refresh,
/// swipe to remove, prominent add button.
struct WatchlistView: View {
    @Environment(AppStore.self) private var store
    @State private var showingAdd: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if store.flights.isEmpty {
                    emptyState
                } else {
                    flightList
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Flights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showingAdd = true
                    } label: {
                        LucideIcon(name: "plus", size: 19, fallback: "plus")
                            .foregroundStyle(Theme.teal)
                    }
                    .accessibilityLabel("Track a flight")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFlightSheet()
            }
            .navigationDestination(for: TrackedFlight.self) { flight in
                FlightDetailView(flight: flight)
            }
        }
        .task {
            if !store.flights.isEmpty {
                await store.refreshAll()
            }
        }
    }

    private var flightList: some View {
        List {
            ForEach(store.sortedFlights) { flight in
                NavigationLink(value: flight) {
                    FlightCardView(flight: flight,
                                   snapshot: store.snapshots[flight.id],
                                   isRefreshing: store.refreshing.contains(flight.id),
                                   onRetry: {
                                       Task { await store.refresh(flight) }
                                   })
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.remove(flight)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refreshAll()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.teal.opacity(0.1))
                    .frame(width: 108, height: 108)
                LucideIcon(name: "radar", size: 48, fallback: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Theme.teal)
            }
            VStack(spacing: 6) {
                Text("No flights tracked yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Add a flight and the engine will watch FAA programs, weather, and your aircraft's inbound chain for early trouble.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                Haptics.tap()
                showingAdd = true
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(name: "plus", size: 16, fallback: "plus")
                    Text("Track a flight")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Theme.teal)
                .clipShape(.capsule)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
