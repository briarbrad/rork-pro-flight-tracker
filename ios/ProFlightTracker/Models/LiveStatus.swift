import Foundation

/// GET /api/flight/live — the cheap main-refresh envelope. ONE AeroAPI query
/// (vs 2 for /flight/status) running the same deterministic analysis the
/// brief runs (compute_phase → predict_times → attach_next_event →
/// analyze_taxi → assess) on a single status pull. Field shapes are shared
/// with /api/brief, so the brief models decode them.
nonisolated struct LiveEnvelope: Codable, Sendable {
    let flight: String?
    let date: String?
    /// When this analysis was computed.
    let generatedAt: String?
    /// When the SOURCE data was pulled — freshness renders from THIS,
    /// never from HTTP-response receipt time.
    let fetchedAt: String?
    let phase: BriefPhase?
    let predictedTimes: BriefPredictedTimes?
    let taxi: BriefTaxi?
    let horizon: BriefHorizon?
    /// scope == "status_only": catches cancellations, diversions, slips,
    /// EDCTs, and taxi anomalies — but no weather, FAA programs, or
    /// equipment chain were consulted at this price point.
    let verdict: BriefVerdict?
    let effects: [BriefEffect]?
    let timezones: BriefTimezones?
    let edctCache: LiveEdctCache?
    /// Delay history across the tracker's scheduled checks — free to attach
    /// here (a DB read), so the trend stays current on cheap refreshes.
    let delayTrend: BriefDelayTrend?
    /// Staleness threshold in seconds; null once the flight is finished.
    let refreshAfterSeconds: Int?
    let aeroapiQueriesUsed: Int?

    enum CodingKeys: String, CodingKey {
        case flight, date, phase, taxi, horizon, verdict, effects, timezones
        case generatedAt = "generated_at"
        case fetchedAt = "fetched_at"
        case predictedTimes = "predicted_times"
        case edctCache = "edct_cache"
        case delayTrend = "delay_trend"
        case refreshAfterSeconds = "refresh_after_seconds"
        case aeroapiQueriesUsed = "aeroapi_queries_used"
    }
}

/// Whether the server re-attached a brief-discovered EDCT from its 45-min
/// cache (`?edct=cached`), so FAA-controlled times survive cheap refreshes.
nonisolated struct LiveEdctCache: Codable, Hashable, Sendable {
    let attached: Bool?
    let cachedAt: String?
    let ttlMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case attached
        case cachedAt = "cached_at"
        case ttlMinutes = "ttl_minutes"
    }
}

/// Persisted essence of the last /api/flight/live pull — the LIVE LAYER.
/// The hero card and its trip timeline render from this on every refresh; the
/// stored brief is enrichment only (EDCT context, forecast windows, effects,
/// verdict narrative) and loses to this layer wherever they disagree.
nonisolated struct StoredLive: Codable, Hashable, Sendable {
    var phase: BriefPhase?
    var predictedTimes: BriefPredictedTimes?
    var taxi: BriefTaxi?
    var timezones: BriefTimezones?
    /// Status-scope cause → effect list from the cheap refresh. Kept so the
    /// flight screen can keep showing CURRENT evidence even after the richer
    /// brief goes stale — optional, so pre-existing persisted snapshots
    /// (without this field) still decode.
    var effects: [BriefEffect]?
    /// verdict.departure_risk at scope "status_only". A LOW here means
    /// "nothing visible in status data", NOT "all clear" — weather and FAA
    /// program risk remain the brief's authority.
    var risk: String?
    var verdictScope: String?
    /// Server staleness threshold, never a polling interval. nil = the
    /// flight is finished — final, stop refreshing it.
    var refreshAfterSeconds: Int?
    var edctCacheAttached: Bool?
    /// Delay history across scheduled checks — optional so pre-existing
    /// persisted snapshots still decode.
    var delayTrend: BriefDelayTrend?
    /// Source-pull time — freshness captions and every advancing clock
    /// (countdowns, elapsed-in-phase) anchor here.
    var fetchedAt: Date

    init(envelope: LiveEnvelope) {
        phase = envelope.phase
        predictedTimes = envelope.predictedTimes
        taxi = envelope.taxi
        timezones = envelope.timezones
        effects = envelope.effects
        risk = envelope.verdict?.departureRisk
        verdictScope = envelope.verdict?.scope
        refreshAfterSeconds = envelope.refreshAfterSeconds
        edctCacheAttached = envelope.edctCache?.attached
        delayTrend = envelope.delayTrend
        fetchedAt = TimeFmt.parseISO(envelope.fetchedAt) ?? Date()
    }

    var riskLevel: RiskLevel? { risk.flatMap { RiskLevel(rawValue: $0.uppercased()) } }

    /// `refresh_after_seconds: null` is the server saying the flight is
    /// finished. Guarded on the phase being terminal too, so a decode gap
    /// can never accidentally freeze a live flight.
    var isFinal: Bool { refreshAfterSeconds == nil && (phase?.isOver ?? false) }

    /// Past the server's own staleness threshold — show the refresh
    /// affordance and age treatment. NOT a poll timer: each refresh costs a
    /// paid query, so refreshes stay user-initiated.
    var isStale: Bool {
        guard let seconds = refreshAfterSeconds else { return false }
        return Date().timeIntervalSince(fetchedAt) > Double(seconds)
    }

    /// The predicted-times entry behind `phase.next_event` — the server
    /// names the key, so no switch on flight state is needed elsewhere.
    var nextEventPredictedTime: BriefPredictedTime? {
        guard let key = phase?.nextEvent, let times = predictedTimes else { return nil }
        switch key {
        case "gate_departure": return times.gateDeparture
        case "takeoff": return times.takeoff
        case "gate_arrival": return times.gateArrival
        default: return nil
        }
    }
}
