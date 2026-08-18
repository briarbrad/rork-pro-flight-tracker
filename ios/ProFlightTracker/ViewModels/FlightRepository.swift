import Foundation
import Observation

/// Data layer: the single owner of tracked flights, their snapshots, and the
/// alert feed, plus their UserDefaults persistence. Pure reads and writes —
/// no networking, no refresh decisions, no alert generation. Views that only
/// display data depend on this instead of the whole app store.
@Observable
final class FlightRepository {
    private enum Keys {
        static let flights = "pft.flights.v1"
        static let snapshots = "pft.snapshots.v1"
        static let alerts = "pft.alerts.v1"
        static let pushToken = "pft.pushToken.v1"
    }

    var flights: [TrackedFlight] = []
    var snapshots: [String: FlightSnapshot] = [:]
    var alerts: [FlightAlert] = []

    /// Placeholder token registered with the engine's tracking service.
    /// Replaced by a real APNs/Expo token when the app ships to devices.
    let pushToken: String

    private let defaults = UserDefaults.standard

    init() {
        if let token = defaults.string(forKey: Keys.pushToken) {
            pushToken = token
        } else {
            let token = "rork-ios-preview-\(UUID().uuidString.lowercased())"
            defaults.set(token, forKey: Keys.pushToken)
            pushToken = token
        }
        flights = load([TrackedFlight].self, key: Keys.flights) ?? []
        snapshots = load([String: FlightSnapshot].self, key: Keys.snapshots) ?? [:]
        alerts = load([FlightAlert].self, key: Keys.alerts) ?? []
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

    // MARK: - Mutations

    func markAlertRead(_ alert: FlightAlert) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }),
              !alerts[index].isRead else { return }
        alerts[index].isRead = true
        persist()
    }

    func markAllAlertsRead() {
        for index in alerts.indices { alerts[index].isRead = true }
        persist()
    }

    /// Inserts a new alert, or — when an alert for the same underlying event
    /// (flightKey + dedupKey) already exists — updates it in place: fresh
    /// content, bumped `updatedAt`, back to unread, moved to the top.
    /// Returns nil when nothing materially changed (no re-notify).
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

    // MARK: - Persistence

    func persist() {
        save(flights, key: Keys.flights)
        save(snapshots, key: Keys.snapshots)
        save(alerts, key: Keys.alerts)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
