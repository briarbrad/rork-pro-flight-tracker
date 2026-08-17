import Foundation

/// A flight on the local watchlist. Mirrors the backend's track_id convention
/// of "FLIGHT_yyyy-MM-dd".
nonisolated struct TrackedFlight: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let ident: String
    let date: String
    var intervalMinutes: Int
    let createdAt: Date

    init(ident: String, date: String, intervalMinutes: Int = 15) {
        self.ident = ident.uppercased()
        self.date = date
        self.id = "\(ident.uppercased())_\(date)"
        self.intervalMinutes = intervalMinutes
        self.createdAt = Date()
    }
}

/// Latest fetched data + risk assessment for one tracked flight. Persisted so
/// the watchlist renders instantly on launch.
nonisolated struct FlightSnapshot: Codable, Hashable, Sendable {
    var flight: AeroFlight?
    var chain: ChainData?
    var metar: [String: MetarObservation]?
    var taf: [String: TafReport]?
    var faa: [String: FaaAirportStatus]?
    var lightning: LightningWrapper?
    /// Route-filtered convective forecast (free). Reference data only — it is
    /// deliberately excluded from the verdict, matching the backend.
    var convective: TcfEnvelope?
    /// International SIGMETs, fetched only when the route leaves CONUS.
    var internationalSigmets: [InternationalSigmet]?
    var assessment: RiskAssessment?
    var brief: StoredBrief?
    var lastRefreshed: Date?
    var refreshError: String?

    /// Codable subset of LightningEnvelope worth persisting.
    nonisolated struct LightningWrapper: Codable, Hashable, Sendable {
        let airport: String?
        let strikesWithin5nm: Int?
        let totalStrikes: Int?
        let rampClosureRisk: String?
        let activityLevel: String?
    }
}
