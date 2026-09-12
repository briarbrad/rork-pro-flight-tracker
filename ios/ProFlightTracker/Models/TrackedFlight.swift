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
    /// Last known aircraft position. Filled from the equipment chain while
    /// the turn is still relevant, then from the usually-free `/api/flight/track`
    /// once the aircraft has pushed (so the day-of map does not depend on a
    /// paid chain refresh). Optional so older snapshots still decode.
    var lastPosition: AircraftPosition?
    var assessment: RiskAssessment?
    var brief: StoredBrief?
    /// Server-computed live layer from /api/flight/live — the render source
    /// for phase and predicted times on every refresh. The brief is
    /// enrichment and loses to this wherever they disagree.
    var live: StoredLive?
    /// SOURCE-pull time of the last refresh (the envelope's `fetched_at`),
    /// not HTTP-response receipt — every freshness caption renders from it.
    var lastRefreshed: Date?
    var refreshError: String?
    /// Set the first time the detail screen auto-runs the brief for this
    /// flight — marked BEFORE the request fires and persisted, so the
    /// auto-run happens exactly once per flight even if it fails or the
    /// user closes the screen mid-run. Manual "Run brief" / "Re-run" stay
    /// available regardless. Optional so old persisted snapshots decode.
    var autoBriefAttempted: Bool?
    /// Per-flight Q&A chat history. Rides the snapshot's existing Codable
    /// persistence, so conversations survive relaunch with no extra storage
    /// code. Optional so old persisted snapshots decode.
    var chatHistory: [ChatTurn]?

    /// The flight is finished — nothing can change, so automatic refreshes
    /// and paid follow-up queries stop. The live layer's
    /// `refresh_after_seconds: null` is authoritative when present; the
    /// milestone-derived phase covers snapshots that never got a live pull
    /// (status-only add flow, or a live decode gap) so a landed/cancelled
    /// flight cannot keep spending AeroAPI credit.
    var isFinal: Bool {
        if live?.isFinal == true { return true }
        guard let flight else { return false }
        switch FlightPhaseDerivation.phase(for: flight) {
        case .arrived, .cancelled: return true
        default: return false
        }
    }

    /// Server-driven staleness gate for AUTOMATIC refreshes (screen-open).
    /// Falls back to 120 s until the first live pull supplies a threshold.
    /// Never a poll timer — refreshes stay user- or navigation-initiated.
    var autoRefreshDue: Bool {
        if isFinal { return false }
        guard let lastRefreshed else { return true }
        let threshold = Double(live?.refreshAfterSeconds ?? 120)
        return Date().timeIntervalSince(lastRefreshed) > threshold
    }

    /// Codable subset of LightningEnvelope worth persisting.
    nonisolated struct LightningWrapper: Codable, Hashable, Sendable {
        let airport: String?
        let strikesWithin5nm: Int?
        let totalStrikes: Int?
        let rampClosureRisk: String?
        let activityLevel: String?
    }
}
