import Foundation

/// Versioned, atomic, file-based persistence for the watchlist, per-flight
/// snapshots, and the alert feed. Replaces the old UserDefaults JSON blobs.
///
/// Layout (Application Support/FlightStore/):
/// - `flights.json`        — the watchlist
/// - `alerts.json`         — the alert feed
/// - `snapshots/<id>.json` — one file per tracked flight's snapshot, so a
///   refresh rewrites ~one flight's data instead of every flight's
///
/// Every file is wrapped in a schema-versioned envelope and written with
/// `.atomic`, so a crash mid-write can never leave a half-written record.
/// A record that fails to decode is logged and skipped — never a crash.
final class FlightDataStore {
    /// Bump when a persisted model changes shape incompatibly, and add a
    /// per-version migration in `read(_:from:)`. Records written by a NEWER
    /// schema than this build understands are skipped, not misread.
    static let schemaVersion = 1

    /// Envelope every record is stored in, so future readers always know
    /// which schema wrote it.
    nonisolated private struct Envelope<T: Codable>: Codable {
        let schemaVersion: Int
        let payload: T
    }

    private enum LegacyKeys {
        static let flights = "pft.flights.v1"
        static let snapshots = "pft.snapshots.v1"
        static let alerts = "pft.alerts.v1"
    }

    private let root: URL
    private let snapshotsDir: URL
    private let fm = FileManager.default

    init() {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        root = base.appendingPathComponent("FlightStore", isDirectory: true)
        snapshotsDir = root.appendingPathComponent("snapshots", isDirectory: true)
        do {
            try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        } catch {
            print("[DataStore] failed to create store directory: \(error)")
        }
    }

    // MARK: - Watchlist

    func loadFlights() -> [TrackedFlight]? {
        read([TrackedFlight].self, from: flightsURL)
    }

    func saveFlights(_ flights: [TrackedFlight]) {
        write(flights, to: flightsURL)
    }

    // MARK: - Alerts

    func loadAlerts() -> [FlightAlert]? {
        read([FlightAlert].self, from: alertsURL)
    }

    func saveAlerts(_ alerts: [FlightAlert]) {
        write(alerts, to: alertsURL)
    }

    // MARK: - Snapshots (one atomic file per flight)

    func loadSnapshots(for ids: [String]) -> [String: FlightSnapshot] {
        var result: [String: FlightSnapshot] = [:]
        for id in ids {
            if let snapshot = read(FlightSnapshot.self, from: snapshotURL(for: id)) {
                result[id] = snapshot
            }
        }
        return result
    }

    func saveSnapshot(_ snapshot: FlightSnapshot, for id: String) {
        write(snapshot, to: snapshotURL(for: id))
    }

    func deleteSnapshot(for id: String) {
        try? fm.removeItem(at: snapshotURL(for: id))
    }

    /// Sanitized ids of every snapshot file on disk — used to sweep orphans
    /// whose flight is no longer tracked.
    func snapshotIdsOnDisk() -> [String] {
        let files = (try? fm.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Maps a flight id to its on-disk snapshot filename stem.
    func sanitizedId(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "_" })
    }

    // MARK: - One-time migration from the old UserDefaults blobs

    /// Moves the legacy UserDefaults JSON blobs into the file store on the
    /// first launch after this update, then clears them. Corrupt legacy blobs
    /// are logged and skipped — the user keeps whatever still decodes.
    func migrateLegacyUserDefaultsIfNeeded() {
        // The flights file existing means this install is already on the
        // file store — legacy keys (if any) were consumed on a prior launch.
        guard !fm.fileExists(atPath: flightsURL.path) else { return }
        let defaults = UserDefaults.standard
        let hasLegacy = defaults.data(forKey: LegacyKeys.flights) != nil
            || defaults.data(forKey: LegacyKeys.snapshots) != nil
            || defaults.data(forKey: LegacyKeys.alerts) != nil
        guard hasLegacy else { return }

        let flights = decodeLegacy([TrackedFlight].self, key: LegacyKeys.flights) ?? []
        let snapshots = decodeLegacy([String: FlightSnapshot].self, key: LegacyKeys.snapshots) ?? [:]
        let alerts = decodeLegacy([FlightAlert].self, key: LegacyKeys.alerts) ?? []

        saveFlights(flights)
        saveAlerts(alerts)
        for (id, snapshot) in snapshots {
            saveSnapshot(snapshot, for: id)
        }
        defaults.removeObject(forKey: LegacyKeys.flights)
        defaults.removeObject(forKey: LegacyKeys.snapshots)
        defaults.removeObject(forKey: LegacyKeys.alerts)
        print("[DataStore] migrated legacy UserDefaults data: \(flights.count) flights, \(snapshots.count) snapshots, \(alerts.count) alerts")
    }

    private func decodeLegacy<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("[DataStore] legacy blob \(key) failed to decode — skipping: \(error)")
            return nil
        }
    }

    // MARK: - Versioned read/write

    private func read<T: Codable>(_ type: T.Type, from url: URL) -> T? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
            guard envelope.schemaVersion <= Self.schemaVersion else {
                print("[DataStore] \(url.lastPathComponent) was written by newer schema v\(envelope.schemaVersion) (this build reads v\(Self.schemaVersion)) — skipping")
                return nil
            }
            // schemaVersion 1 is the first file-store schema; when v2 lands,
            // upgrade older payloads here instead of dropping them.
            return envelope.payload
        } catch {
            print("[DataStore] corrupt record \(url.lastPathComponent) skipped: \(error)")
            return nil
        }
    }

    private func write<T: Codable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(
                Envelope(schemaVersion: Self.schemaVersion, payload: value))
            try data.write(to: url, options: .atomic)
        } catch {
            print("[DataStore] failed to write \(url.lastPathComponent): \(error)")
        }
    }

    private var flightsURL: URL { root.appendingPathComponent("flights.json") }
    private var alertsURL: URL { root.appendingPathComponent("alerts.json") }

    private func snapshotURL(for id: String) -> URL {
        snapshotsDir.appendingPathComponent("\(sanitizedId(id)).json")
    }
}
