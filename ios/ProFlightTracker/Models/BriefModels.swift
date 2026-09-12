import Foundation

/// GET /api/brief — horizon-gated deterministic analysis + LLM prompt payload.
/// The verdict, branch, and horizon are computed server-side and rendered
/// directly; the LLM payload is used only for the optional prose narrative.
nonisolated struct BriefEnvelope: Codable, Sendable {
    let flight: String?
    let date: String?
    let phase: BriefPhase?
    let taxi: BriefTaxi?
    let position: BriefPosition?
    let horizon: BriefHorizon?
    let verdict: BriefVerdict?
    let branchClassification: BriefBranch?
    let predictedTimes: BriefPredictedTimes?
    let tafWindows: BriefTafWindows?
    let timezones: BriefTimezones?
    let effects: [BriefEffect]?
    let sourcesConsulted: [String]?
    let sourcesExcluded: [String: String]?
    let refreshAfterSeconds: Int?
    let llmPayload: BriefLlmPayload?
    let delayTrend: BriefDelayTrend?
    let aeroapiQueriesUsed: Int?
    /// Passenger-facing prediction for Simple mode. Optional JSON so older
    /// backends (and unexpected shapes) still decode — parsed into
    /// `BriefSimpleSummary` on persist.
    let simpleSummary: JSONValue?
    /// v1.13 story layer — optional so older backends still decode.
    let status: StoryStatus?
    let impactMinutes: Int?
    let causes: [StoryCause]?
    let outlook: StoryOutlook?

    enum CodingKeys: String, CodingKey {
        case flight, date, horizon, verdict, effects, timezones, phase, taxi, position
        case branchClassification = "branch_classification"
        case predictedTimes = "predicted_times"
        case tafWindows = "taf_windows"
        case sourcesConsulted = "sources_consulted"
        case sourcesExcluded = "sources_excluded"
        case refreshAfterSeconds = "refresh_after_seconds"
        case llmPayload = "llm_payload"
        case delayTrend = "delay_trend"
        case aeroapiQueriesUsed = "aeroapi_queries_used"
        case simpleSummary = "simple_summary"
        case status, causes, outlook
        case impactMinutes
        case impact_minutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flight = try container.decodeIfPresent(String.self, forKey: .flight)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        phase = try container.decodeIfPresent(BriefPhase.self, forKey: .phase)
        taxi = try container.decodeIfPresent(BriefTaxi.self, forKey: .taxi)
        position = try container.decodeIfPresent(BriefPosition.self, forKey: .position)
        horizon = try container.decodeIfPresent(BriefHorizon.self, forKey: .horizon)
        verdict = try container.decodeIfPresent(BriefVerdict.self, forKey: .verdict)
        branchClassification = try container.decodeIfPresent(BriefBranch.self, forKey: .branchClassification)
        predictedTimes = try container.decodeIfPresent(BriefPredictedTimes.self, forKey: .predictedTimes)
        tafWindows = try container.decodeIfPresent(BriefTafWindows.self, forKey: .tafWindows)
        timezones = try container.decodeIfPresent(BriefTimezones.self, forKey: .timezones)
        effects = try container.decodeIfPresent([BriefEffect].self, forKey: .effects)
        sourcesConsulted = try container.decodeIfPresent([String].self, forKey: .sourcesConsulted)
        sourcesExcluded = try container.decodeIfPresent([String: String].self, forKey: .sourcesExcluded)
        refreshAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshAfterSeconds)
        llmPayload = try container.decodeIfPresent(BriefLlmPayload.self, forKey: .llmPayload)
        delayTrend = try container.decodeIfPresent(BriefDelayTrend.self, forKey: .delayTrend)
        aeroapiQueriesUsed = try container.decodeIfPresent(Int.self, forKey: .aeroapiQueriesUsed)
        simpleSummary = try container.decodeIfPresent(JSONValue.self, forKey: .simpleSummary)
        status = try container.decodeIfPresent(StoryStatus.self, forKey: .status)
        causes = try container.decodeIfPresent([StoryCause].self, forKey: .causes)
        outlook = try container.decodeIfPresent(StoryOutlook.self, forKey: .outlook)
        impactMinutes = try container.decodeIfPresent(Int.self, forKey: .impactMinutes)
            ?? container.decodeIfPresent(Int.self, forKey: .impact_minutes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(flight, forKey: .flight)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(phase, forKey: .phase)
        try container.encodeIfPresent(taxi, forKey: .taxi)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(horizon, forKey: .horizon)
        try container.encodeIfPresent(verdict, forKey: .verdict)
        try container.encodeIfPresent(branchClassification, forKey: .branchClassification)
        try container.encodeIfPresent(predictedTimes, forKey: .predictedTimes)
        try container.encodeIfPresent(tafWindows, forKey: .tafWindows)
        try container.encodeIfPresent(timezones, forKey: .timezones)
        try container.encodeIfPresent(effects, forKey: .effects)
        try container.encodeIfPresent(sourcesConsulted, forKey: .sourcesConsulted)
        try container.encodeIfPresent(sourcesExcluded, forKey: .sourcesExcluded)
        try container.encodeIfPresent(refreshAfterSeconds, forKey: .refreshAfterSeconds)
        try container.encodeIfPresent(llmPayload, forKey: .llmPayload)
        try container.encodeIfPresent(delayTrend, forKey: .delayTrend)
        try container.encodeIfPresent(aeroapiQueriesUsed, forKey: .aeroapiQueriesUsed)
        try container.encodeIfPresent(simpleSummary, forKey: .simpleSummary)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(impactMinutes, forKey: .impactMinutes)
        try container.encodeIfPresent(causes, forKey: .causes)
        try container.encodeIfPresent(outlook, forKey: .outlook)
    }
}

/// Server-recorded history of how this flight's delay has moved across the
/// background tracker's scheduled checks. Written server-side on the existing
/// polling cadence and classified server-side — the client renders the series
/// and direction verbatim and never re-derives a trend.
nonisolated struct BriefDelayTrend: Codable, Hashable, Sendable {
    let snapshots: [BriefDelaySnapshot]?
    /// "widening" / "narrowing" / "steady"; nil = not enough checks yet.
    /// One check is a data point, not a trend — nil means show NOTHING,
    /// never a false "holding steady".
    let direction: String?
    let checks: Int?

    var directionCode: String? {
        guard let direction, !direction.isEmpty else { return nil }
        return direction.lowercased()
    }

    /// Renderable only with a server-classified direction AND ≥2 points.
    var hasTrend: Bool {
        directionCode != nil && (snapshots?.count ?? 0) >= 2
    }

    var orderedSnapshots: [BriefDelaySnapshot] { snapshots ?? [] }
}

/// One scheduled check's outcome: when it ran and how far off schedule the
/// flight's next gate event was at that moment.
nonisolated struct BriefDelaySnapshot: Codable, Hashable, Sendable {
    let checkedAt: String?
    let deltaMinutes: Double?
    let risk: String?

    enum CodingKeys: String, CodingKey {
        case risk
        case checkedAt = "checked_at"
        case deltaMinutes = "delta_minutes"
    }
}

/// The flight's current lifecycle state — the primary state the screen is
/// organised around, read BEFORE horizon. The headline is always the next
/// event, never the schedule: a flight 100 minutes into a taxi hold doesn't
/// care that it left the gate 5 minutes early.
nonisolated struct BriefPhase: Codable, Hashable, Sendable {
    let phase: String?
    let phaseLabel: String?
    let phaseDetail: String?
    let elapsedInPhaseMin: Int?
    let nextEvent: String?
    let nextEventLabel: String?
    let nextEventLocalDisplay: String?
    let nextEventBasis: String?
    let nextEventStatus: String?
    let nextEventOverdue: Bool?
    let minutesToNextEvent: Int?

    enum CodingKeys: String, CodingKey {
        case phase
        case phaseLabel = "phase_label"
        case phaseDetail = "phase_detail"
        case elapsedInPhaseMin = "elapsed_in_phase_min"
        case nextEvent = "next_event"
        case nextEventLabel = "next_event_label"
        case nextEventLocalDisplay = "next_event_local_display"
        case nextEventBasis = "next_event_basis"
        case nextEventStatus = "next_event_status"
        case nextEventOverdue = "next_event_overdue"
        case minutesToNextEvent = "minutes_to_next_event"
    }

    /// PRE_GATE / TAXI_OUT / AIRBORNE / TAXI_IN / ARRIVED / CANCELLED.
    var code: String { (phase ?? "").uppercased() }

    /// The flight is physically in motion between gate and gate — the window
    /// where live position and taxi assessments matter most.
    var isEnRoute: Bool { ["TAXI_OUT", "AIRBORNE", "TAXI_IN"].contains(code) }
    var isOver: Bool { code == "ARRIVED" || code == "CANCELLED" }
    var isCancelled: Bool { code == "CANCELLED" }

    /// FAA-assigned next-event time — materially harder than an estimate.
    var isControlled: Bool { nextEventStatus?.uppercased() == "CONTROLLED" }

    /// The predicted time has passed and the event still hasn't happened —
    /// this is getting worse, not resolving.
    var isOverdue: Bool { nextEventOverdue ?? false }
}

/// Whether the current taxi wait is abnormal, judged per-airport (30 min is
/// routine at JFK and alarming at DCA). `summary` is written server-side to
/// be rendered verbatim. The key is always present — check `applicable`.
nonisolated struct BriefTaxi: Codable, Hashable, Sendable {
    let applicable: Bool?
    let assessment: String?
    let elapsedMin: Int?
    let typicalMin: Int?
    let predictedTotalMin: Int?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case applicable, assessment, summary
        case elapsedMin = "elapsed_min"
        case typicalMin = "typical_min"
        case predictedTotalMin = "predicted_total_min"
    }

    var isApplicable: Bool { applicable ?? false }
    /// NORMAL / ELEVATED / EXTENDED.
    var assessmentCode: String { (assessment ?? "").uppercased() }
}

/// Live aircraft position + whether it's actually moving — parked in a queue
/// and rolling toward the runway are the same dot on a map and completely
/// different experiences. `available: false` means no position is being
/// reported (surface ADS-B is patchy) — say nothing rather than "unknown".
nonisolated struct BriefPosition: Codable, Hashable, Sendable {
    let available: Bool?
    let movement: String?
    let movementLabel: String?
    let latitude: Double?
    let longitude: Double?
    let groundspeedKts: Double?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case available, movement, latitude, longitude, note
        case movementLabel = "movement_label"
        case groundspeedKts = "groundspeed_kts"
    }

    var isAvailable: Bool { available ?? false }
    /// STOPPED / TAXIING / TAKEOFF_ROLL / AIRBORNE / ON_GROUND / UNKNOWN.
    var movementCode: String { (movement ?? "UNKNOWN").uppercased() }
}

/// Server-computed answer to "when does this flight actually go". Precedence
/// (actual > EDCT > estimate > schedule) is encoded upstream — the client
/// renders these verbatim and never rebuilds predictions from raw sources.
nonisolated struct BriefPredictedTimes: Codable, Hashable, Sendable {
    let gateDeparture: BriefPredictedTime?
    let takeoff: BriefPredictedTime?
    let gateArrival: BriefPredictedTime?
    let uncertaintyMinutes: Int?
    let uncertaintyNote: String?
    let edct: BriefEdct?

    enum CodingKeys: String, CodingKey {
        case gateDeparture = "gate_departure"
        case takeoff
        case gateArrival = "gate_arrival"
        case uncertaintyMinutes = "uncertainty_minutes"
        case uncertaintyNote = "uncertainty_note"
        case edct
    }
}

/// One predicted time with its provenance. `status` vocabulary:
/// ACTUAL / CONTROLLED / ESTIMATED / DERIVED / SCHEDULED / UNKNOWN.
nonisolated struct BriefPredictedTime: Codable, Hashable, Sendable {
    let time: String?
    let timeLocal: String?
    let localDisplay: String?
    let utcDisplay: String?
    let timezone: String?
    let status: String?
    let basis: String?
    let delayVsScheduleMin: Int?

    enum CodingKeys: String, CodingKey {
        case time, status, basis, timezone
        case timeLocal = "time_local"
        case localDisplay = "local_display"
        case utcDisplay = "utc_display"
        case delayVsScheduleMin = "delay_vs_schedule_min"
    }

    /// Airport-local string built server-side — gate/takeoff in the origin's
    /// zone, arrival in the destination's. Rendered as-is when the backend
    /// resolved a zone; when it didn't (`timezone: ""`, which happens on plenty
    /// of routes) its string is bare Zulu, so the client's own airport-zone
    /// lookup takes over rather than showing the wrong-looking hour.
    func displayTime(fallbackZone: TimeZone? = nil) -> String {
        if hasResolvedZone, let local = localDisplay, !local.isEmpty { return local }
        if let fallbackZone, time != nil {
            return TimeFmt.clockWithZone(time, zone: fallbackZone)
        }
        if let local = localDisplay, !local.isEmpty { return local }
        if let utc = utcDisplay, !utc.isEmpty { return utc }
        return TimeFmt.clock(time)
    }

    /// True once a zone is known from either end — the backend's or the client's.
    func hasZone(fallback: TimeZone?) -> Bool { hasResolvedZone || fallback != nil }

    /// False when the backend couldn't resolve a zone for this time.
    var hasResolvedZone: Bool { !(timezone ?? "").isEmpty }

    var statusCode: String { status?.uppercased() ?? "UNKNOWN" }
    var isControlled: Bool { statusCode == "CONTROLLED" }
    var isActual: Bool { statusCode == "ACTUAL" }
    var isScheduledOnly: Bool { statusCode == "SCHEDULED" }
    var isUnknown: Bool { statusCode == "UNKNOWN" || time == nil }
}

/// FAA-assigned wheels-up slot (EDCT). Non-null only when traffic management
/// has actually controlled this flight — the most important fact on screen.
nonisolated struct BriefEdct: Codable, Hashable, Sendable {
    let edct: String?
    let localDisplay: String?
    let utcDisplay: String?
    let asOf: String?
    let assignedVia: String?

    enum CodingKeys: String, CodingKey {
        case edct
        case localDisplay = "local_display"
        case utcDisplay = "utc_display"
        case asOf = "as_of"
        case assignedVia = "assigned_via"
    }

    /// Prefers the backend's airport-local string, then the client's own zone
    /// for the departure airport — an EDCT is always a wheels-up time at the
    /// origin, so it reads in origin-local time.
    func displayTime(fallbackZone: TimeZone? = nil) -> String {
        if let local = localDisplay, !local.isEmpty, !local.hasSuffix("Z") { return local }
        if let fallbackZone, edct != nil {
            return TimeFmt.clockWithZone(edct, zone: fallbackZone)
        }
        if let local = localDisplay, !local.isEmpty { return local }
        if let utc = utcDisplay, !utc.isEmpty { return utc }
        return TimeFmt.clock(edct)
    }
}

/// Olson zones the backend used for the local strings, origin and destination.
nonisolated struct BriefTimezones: Codable, Hashable, Sendable {
    let origin: String?
    let destination: String?

    /// "New York" / "Rome" — the city half of the zone id, for captions.
    static func cityName(_ zone: String?) -> String? {
        guard let zone, !zone.isEmpty else { return nil }
        return zone.split(separator: "/").last?.replacingOccurrences(of: "_", with: " ")
    }
}

/// Terminal-forecast assessment for the ±60 minutes around each predicted
/// time. This is the only weather block that escalates `departure_risk`, and
/// only through prevailing (FM) conditions — TEMPO/PROB groups surface as
/// WATCH and deliberately never move the headline.
nonisolated struct BriefTafWindows: Codable, Hashable, Sendable {
    let departure: BriefTafWindow?
    let arrival: BriefTafWindow?
}

nonisolated struct BriefTafWindow: Codable, Hashable, Sendable {
    let airport: String?
    let prevailingCategory: String?
    let worstConditionalCategory: String?
    let significantWeather: [String]?
    let maxGustKts: Double?
    let windShear: Bool?
    let available: Bool?
    let note: String?
    let periods: [BriefTafPeriodWindow]?

    enum CodingKeys: String, CodingKey {
        case airport, periods, note, available
        case prevailingCategory = "prevailing_category"
        case worstConditionalCategory = "worst_conditional_category"
        case significantWeather = "significant_weather"
        case maxGustKts = "max_gust_kts"
        case windShear = "wind_shear"
    }

    var isAvailable: Bool { available ?? false }
    var prevailing: String { (prevailingCategory ?? "UNKNOWN").uppercased() }
    var worstConditional: String { (worstConditionalCategory ?? "UNKNOWN").uppercased() }

    /// Prevailing IFR/LIFR is what escalates the verdict; MVFR does not.
    var prevailingEscalates: Bool { prevailing == "IFR" || prevailing == "LIFR" }

    /// A TEMPO/PROB group worse than what's actually forecast — "keep an eye
    /// on it", not "replan".
    var hasConditionalDeterioration: Bool {
        BriefTafWindow.categoryRank(worstConditional) > BriefTafWindow.categoryRank(prevailing)
    }

    var gustText: String? {
        guard let gust = maxGustKts, gust > 0 else { return nil }
        return "Gusts to \(Int(gust)) kt"
    }

    /// VFR < MVFR < IFR < LIFR; UNKNOWN sorts lowest so it never reads as worse.
    static func categoryRank(_ category: String) -> Int {
        switch category {
        case "VFR": return 1
        case "MVFR": return 2
        case "IFR": return 3
        case "LIFR": return 4
        default: return 0
        }
    }
}

nonisolated struct BriefTafPeriodWindow: Codable, Hashable, Sendable {
    let fromLocal: String?
    let category: String?
    let conditional: Bool?
    let changeIndicator: String?
    let ceilingFt: Double?
    let visibilitySm: String?
    let windKts: Double?
    let gustKts: Double?
    let probability: JSONValue?
    let weather: String?

    enum CodingKeys: String, CodingKey {
        case category, conditional, probability, weather
        case fromLocal = "from_local"
        case changeIndicator = "change_indicator"
        case ceilingFt = "ceiling_ft"
        case visibilitySm = "visibility_sm"
        case windKts = "wind_kts"
        case gustKts = "gust_kts"
    }

    var categoryCode: String { (category ?? "UNKNOWN").uppercased() }
    var isConditional: Bool { conditional ?? false }

    /// "TEMPO 40%" / "FM" — the group this period came from.
    var groupLabel: String {
        let indicator = changeIndicator ?? (isConditional ? "TEMPO" : "FM")
        if let probability = probability?.intValue { return "\(indicator) \(probability)%" }
        return indicator
    }

    /// "Ceiling 3,500 ft · 6+ sm · wind 7 kt" style one-liner.
    var detailLine: String? {
        var parts: [String] = []
        if let ceiling = ceilingFt { parts.append("Ceiling \(Int(ceiling)) ft") }
        if let vis = visibilitySm, !vis.isEmpty { parts.append("\(vis) sm") }
        if let wind = windKts, wind > 0 {
            var text = "wind \(Int(wind)) kt"
            if let gust = gustKts, gust > 0 { text += " g\(Int(gust))" }
            parts.append(text)
        }
        if let weather, !weather.isEmpty { parts.append(weather) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One backend finding expressed as cause → effect ON THIS FLIGHT, with a
/// server-computed severity (ACTION / WATCH / INFO). Severity encodes
/// directionality (e.g. a GDP at the origin is INFO for a departure) — the
/// client must never re-derive urgency from raw conditions. The array arrives
/// pre-sorted ACTION → WATCH → INFO and is rendered top-down.
nonisolated struct BriefEffect: Codable, Hashable, Sendable {
    let cause: String?
    let effect: String?
    let severity: String?
    let source: String?

    var severityCode: String { severity?.uppercased() ?? "INFO" }
}

nonisolated struct BriefHorizon: Codable, Sendable {
    let hoursToDeparture: Double?
    let band: String?
    let bandGuidance: String?
    let referenceBasis: String?

    enum CodingKeys: String, CodingKey {
        case hoursToDeparture = "hours_to_departure"
        case band
        case bandGuidance = "band_guidance"
        case referenceBasis = "reference_basis"
    }

    /// "in ~15h" / "in 90 min" style phrasing.
    var departsInText: String? {
        guard let hours = hoursToDeparture else { return nil }
        if hours < 0 { return "departed" }
        if hours < 2 { return "in \(Int((hours * 60).rounded())) min" }
        return "in ~\(Int(hours.rounded()))h"
    }
}

nonisolated struct BriefVerdict: Codable, Sendable {
    let departureRisk: String?
    let confidence: String?
    let confidenceBasis: String?
    let drivers: [String]?
    /// "status_only" on /api/flight/live verdicts — no weather, FAA
    /// programs, or equipment chain were consulted at that price point.
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case departureRisk = "departure_risk"
        case confidence
        case confidenceBasis = "confidence_basis"
        case drivers, scope
    }

    var riskLevel: RiskLevel? {
        departureRisk.flatMap { RiskLevel(rawValue: $0.uppercased()) }
    }

    var isLowConfidence: Bool {
        confidence?.uppercased() == "LOW"
    }
}

nonisolated struct BriefBranch: Codable, Sendable {
    let branch: String?
    let branchLabel: String?
    let evidence: [String]?
    let activeProgramCount: Int?

    enum CodingKeys: String, CodingKey {
        case branch
        case branchLabel = "branch_label"
        case evidence
        case activeProgramCount = "active_program_count"
    }

    /// Explicit "too far out to assess any delay mechanism" signal.
    var isNotApplicable: Bool { branch?.uppercased() == "NOT_APPLICABLE" }
}

/// Ready-to-send LLM prompt from the backend. `system` embeds the analytical
/// methodology and guardrails and must be sent verbatim; `facts` is the
/// horizon-filtered fact set — nothing may be added to it.
nonisolated struct BriefLlmPayload: Codable, Hashable, Sendable {
    let system: String?
    let user: String?
    let facts: JSONValue?
}

/// One turn of the per-flight Q&A chat. `role` is "user" or "assistant",
/// mirrored verbatim to the backend's /api/chat contract. The endpoint is
/// stateless, so the full turn list is sent on every request.
nonisolated struct ChatTurn: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    let role: String
    let content: String

    var isUser: Bool { role == "user" }
}

/// Persisted essence of the last brief run for a tracked flight. This is the
/// ONLY flight-level verdict in the app — the client signal engine never
/// produces one. Its excluded sources also mute matching live signals/alerts.
nonisolated struct StoredBrief: Codable, Hashable, Sendable {
    let risk: String?
    let confidence: String?
    let confidenceBasis: String?
    let drivers: [String]
    let branch: String?
    let branchLabel: String?
    let branchEvidence: [String]
    let band: String?
    let hoursToDeparture: Double?
    let sourcesConsulted: [String]
    let sourcesExcluded: [String: String]
    // Optional so briefs persisted before these blocks existed still decode.
    var predictedTimes: BriefPredictedTimes?
    var tafWindows: BriefTafWindows?
    var timezones: BriefTimezones?
    var effects: [BriefEffect]?
    var phase: BriefPhase?
    var taxi: BriefTaxi?
    var position: BriefPosition?
    var refreshAfterSeconds: Int?
    /// Set by the refresh pipeline when live milestones contradict this
    /// brief's phase — the brief no longer describes reality and must wear
    /// the stale treatment regardless of the server's staleness threshold.
    var contradictedByLiveData: Bool?
    /// Delay history across the tracker's scheduled checks — optional so
    /// briefs persisted before this field existed still decode.
    var delayTrend: BriefDelayTrend?
    /// The ready-to-send prompt payload this brief shipped with. Persisted so
    /// the chat feature can ground follow-up questions in the same
    /// horizon-filtered facts after a relaunch. Optional so old briefs decode.
    var llmPayload: BriefLlmPayload?
    var narrative: String?
    var narrativeFailed: Bool
    /// Optional so briefs persisted before `simple_summary` existed still decode.
    var simpleSummary: BriefSimpleSummary?
    /// v1.13 story layer — optional so briefs persisted before these
    /// fields existed still decode.
    var status: StoryStatus?
    var impactMinutes: Int?
    var causes: [StoryCause]?
    var outlook: StoryOutlook?
    let runAt: Date

    init(envelope: BriefEnvelope) {
        risk = envelope.verdict?.departureRisk
        confidence = envelope.verdict?.confidence
        confidenceBasis = envelope.verdict?.confidenceBasis
        drivers = envelope.verdict?.drivers ?? []
        branch = envelope.branchClassification?.branch
        branchLabel = envelope.branchClassification?.branchLabel
        branchEvidence = envelope.branchClassification?.evidence ?? []
        band = envelope.horizon?.band
        hoursToDeparture = envelope.horizon?.hoursToDeparture
        sourcesConsulted = envelope.sourcesConsulted ?? []
        sourcesExcluded = envelope.sourcesExcluded ?? [:]
        predictedTimes = envelope.predictedTimes
        tafWindows = envelope.tafWindows
        timezones = envelope.timezones
        effects = envelope.effects
        phase = envelope.phase
        taxi = envelope.taxi
        position = envelope.position
        refreshAfterSeconds = envelope.refreshAfterSeconds
        delayTrend = envelope.delayTrend
        llmPayload = envelope.llmPayload
        narrative = nil
        narrativeFailed = false
        simpleSummary = BriefSimpleSummary.parse(envelope.simpleSummary)
        status = envelope.status
        impactMinutes = envelope.impactMinutes
        causes = envelope.causes
        outlook = envelope.outlook
        runAt = Date()
    }

    var riskLevel: RiskLevel? {
        risk.flatMap { RiskLevel(rawValue: $0.uppercased()) }
    }

    var isLowConfidence: Bool { confidence?.uppercased() == "LOW" }

    /// Branch NOT_APPLICABLE = the delay mechanisms can't even form yet.
    var isTooEarly: Bool { branch?.uppercased() == "NOT_APPLICABLE" }

    /// LOW risk at LOW confidence is "nothing visible yet", not "fine" —
    /// neutral states must never wear the reassuring green.
    var isNeutral: Bool { isTooEarly || (riskLevel == .low && isLowConfidence) }

    /// Hours to departure right now, advanced from the value at run time.
    var hoursToDepartureNow: Double? {
        hoursToDeparture.map { $0 - Date().timeIntervalSince(runAt) / 3600 }
    }

    /// Server order, verbatim. The backend pre-sorts ACTION → WATCH → INFO,
    /// so the client renders top-down and never re-ranks.
    var orderedEffects: [BriefEffect] { effects ?? [] }

    var hasEffects: Bool { !(effects ?? []).isEmpty }

    /// Forecast windows worth rendering (an unavailable window with no note is
    /// nothing to show).
    var hasForecastWindows: Bool {
        [tafWindows?.departure, tafWindows?.arrival].contains {
            guard let window = $0 else { return false }
            return window.isAvailable || !(window.note ?? "").isEmpty
        }
    }

    /// The full predicted-times entry behind `phase.next_event` — the backend
    /// names the key, so no switch on flight state is ever needed.
    var nextEventPredictedTime: BriefPredictedTime? {
        guard let key = phase?.nextEvent, let times = predictedTimes else { return nil }
        switch key {
        case "gate_departure": return times.gateDeparture
        case "takeoff": return times.takeoff
        case "gate_arrival": return times.gateArrival
        default: return nil
        }
    }

    /// Minutes to the next event as of NOW, advanced from the value at run
    /// time. Negative = the predicted time has slipped past while the brief
    /// sat on screen.
    var minutesToNextEventNow: Int? {
        guard let minutes = phase?.minutesToNextEvent else { return nil }
        let elapsed = Int(Date().timeIntervalSince(runAt) / 60)
        return minutes - elapsed
    }

    /// Minutes in the current phase as of NOW — the server's value is frozen
    /// at brief-run time, so rendering it verbatim shows "In phase 2 min"
    /// forever. Client-derived phases carry no elapsed value (nil).
    var elapsedInPhaseMinNow: Int? {
        guard let elapsed = phase?.elapsedInPhaseMin else { return nil }
        return elapsed + Int(Date().timeIntervalSince(runAt) / 60)
    }

    /// Past the server's staleness threshold (`refresh_after_seconds`) — the
    /// brief no longer describes the flight's current state. This is when to
    /// grey the verdict and suggest a re-run, NOT a polling interval: the
    /// endpoint costs paid queries, so refresh stays user-initiated.
    var isStale: Bool {
        if contradictedByLiveData == true { return true }
        guard let seconds = refreshAfterSeconds else { return false }
        return Date().timeIntervalSince(runAt) > Double(seconds)
    }
}
