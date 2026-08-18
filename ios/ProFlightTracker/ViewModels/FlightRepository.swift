import Foundation
import Observation

/// Data layer: the single owner of tracked flights, their snapshots, and the
/// alert feed. Pure reads and writes — no networking, no refresh decisions,
/// no alert generation. Backed by the versioned, atomic file store; performs
/// legacy UserDefaults migration and TTL pruning once at launch.
@Observable
final class FlightRepository {
    /// Mirrors the backend's 36-hour tracked-flight expiry: a flight (and its
    /// snapshot) is pruned 36 h after its best-known arrival/departure time.
    static let flightTTL: TimeInterval = 36 * 3600

    var flights: [TrackedFlight] = []
    var snapshots: [String: FlightSnapshot] = [:]
    var alerts: [FlightAlert] = []

    /// Placeholder token registered with the engine's tracking service.
    /// Replaced by a real APNs/Expo token when the app ships to devices.
    /// Stays in UserDefaults — it's a scalar, not a data blob.
    let pushToken: String

    private let store: FlightDataStore

    init(store: FlightDataStore = FlightDataStore()) {
        self.store = store

        let defaults = UserDefaults.standard
        let tokenKey = "pft.pushToken.v1"
        if let token = defaults.string(forKey: tokenKey) {
            pushToken = token
        } else {
            let token = "rork-ios-preview-\(UUID().uuidString.lowercased())"
            defaults.set(token, forKey: tokenKey)
            pushToken = token
        }

        store.migrateLegacyUserDefaultsIfNeeded()
        flights = store.loadFlights() ?? []
        snapshots = store.loadSnapshots(for: flights.map(\.id))
        alerts = store.loadAlerts() ?? []
        pruneExpired()
    }

    // MARK: - Derived reads

    var sortedFlights: [TrackedFlight] {
        flights.sorted { lhs, rhs in
            let lhsDate = TimeFmt.parseISO(snapshots[lhs.id]?.flight?.scheduledOut) ?? .distantFuture
            let rhsDate = TimeFmt.parseISO(snapshots[rhs.id]?.flight?.scheduledOut) ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// Tab badge counts only unread DETERIORATIONS — "eased/improved" news
    /// sits in the drawer without demanding attention.
    var unreadAlertCount: Int { alerts.filter { !$0.isRead && !$0.isImprovement }.count }

    func alerts(for flightKey: String) -> [FlightAlert] {
        alerts.filter { $0.flightKey == flightKey }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func trackedFlight(forKey key: String) -> TrackedFlight? {
        flights.first { $0.id == key }
    }

    // MARK: - Watchlist mutations

    func add(_ flight: TrackedFlight, snapshot: FlightSnapshot) {
        flights.append(flight)
        snapshots[flight.id] = snapshot
        store.saveFlights(flights)
        store.saveSnapshot(snapshot, for: flight.id)
    }

    func remove(_ flightId: String) {
        flights.removeAll { $0.id == flightId }
        snapshots[flightId] = nil
        store.saveFlights(flights)
        store.deleteSnapshot(for: flightId)
    }

    /// Persists one flight's snapshot after the caller updated it in place —
    /// exactly one small atomic file write per refresh.
    func saveSnapshot(for flightId: String) {
        guard let snapshot = snapshots[flightId] else {
            store.deleteSnapshot(for: flightId)
            return
        }
        store.saveSnapshot(snapshot, for: flightId)
    }

    // MARK: - Alert mutations

    func markAlertRead(_ alert: FlightAlert) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }),
              !alerts[index].isRead else { return }
        alerts[index].isRead = true
        saveAlerts()
    }

    func markAllAlertsRead() {
        for index in alerts.indices { alerts[index].isRead = true }
        saveAlerts()
    }

    /// Inserts a new alert, or — when an alert for the same underlying event
    /// (flightKey + dedupKey) already exists — updates it in place: fresh
    /// content, bumped `updatedAt`, back to unread, moved to the top.
    /// Returns nil when nothing materially changed (no re-notify).
    /// The caller batches `saveAlerts()` after its upserts.
    @discardableResult
    func upsertAlert(_ candidate: FlightAlert) -> FlightAlert? {
        guard let index = alerts.firstIndex(where: {
            $0.flightKey == candidate.flightKey && $0.dedupKey == candidate.dedupKey
        }) else {
            alerts.insert(candidate, at: 0)
            return candidate
        }
        var existing = alerts[index]
        guard existing.title != candidate.title
            || existing.message != candidate.message
            || existing.level != candidate.level else { return nil }
        existing.title = candidate.title
        existing.message = candidate.message
        existing.level = candidate.level
        existing.icon = candidate.icon
        existing.isImprovement = candidate.isImprovement
        existing.changeNote = candidate.changeNote ?? existing.changeNote
        existing.updatedAt = Date()
        existing.isRead = false
        alerts.remove(at: index)
        alerts.insert(existing, at: 0)
        return existing
    }

    /// Caps the feed so an eventful season can't grow storage unbounded.
    func trimAlerts(to maxCount: Int = 300) {
        if alerts.count > maxCount { alerts = Array(alerts.prefix(maxCount)) }
    }

    func saveAlerts() {
        store.saveAlerts(alerts)
    }

    // MARK: - TTL pruning

    /// Launch-time sweep: expired flights (and their snapshot files), orphan
    /// snapshot files, and alerts whose flight is gone and that haven't
    /// updated within the TTL. Recent alert history for still-tracked
    /// flights is kept.
    private func pruneExpired() {
        let now = Date()
        var removedIds: [String] = []
        flights.removeAll { flight in
            guard now.timeIntervalSince(expiryReference(for: flight)) > Self.flightTTL else {
                return false
            }
            removedIds.append(flight.id)
            return true
        }
        for id in removedIds {
            snapshots[id] = nil
            store.deleteSnapshot(for: id)
        }

        // Orphan snapshot files (flight removed on a previous run, file left).
        let validStems = Set(flights.map { store.sanitizedId($0.id) })
        for stem in store.snapshotIdsOnDisk() where !validStems.contains(stem) {
            store.deleteSnapshot(for: stem)
        }

        let validIds = Set(flights.map(\.id))
        let alertCountBefore = alerts.count
        alerts.removeAll { alert in
            !validIds.contains(alert.flightKey)
                && now.timeIntervalSince(alert.updatedAt) > Self.flightTTL
        }
        trimAlerts()

        if !removedIds.isEmpty {
            store.saveFlights(flights)
            print("[Repository] pruned \(removedIds.count) expired flight(s)")
        }
        if alerts.count != alertCountBefore {
            saveAlerts()
        }
    }

    /// The moment a flight's 36 h expiry clock starts: its best-known arrival,
    /// else scheduled arrival, else scheduled departure, else the end of its
    /// tracked calendar day, else when the user added it.
    private func expiryReference(for flight: TrackedFlight) -> Date {
        let leg = snapshots[flight.id]?.flight
        if let iso = leg?.actualIn ?? leg?.scheduledIn ?? leg?.scheduledOut,
           let date = TimeFmt.parseISO(iso) {
            return date
        }
        if let day = Self.dayFormatter.date(from: flight.date) {
            return day.addingTimeInterval(24 * 3600)
        }
        return flight.createdAt
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
