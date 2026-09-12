import Foundation

/// Optional-endpoint probe: 404/501 means the server has not shipped the
/// route yet (hide the UI); any other failure is a real error.
nonisolated enum OptionalEndpoint<T: Sendable>: Sendable {
    case value(T)
    case missing
    case failed(String)

    var value: T? {
        if case .value(let value) = self { return value }
        return nil
    }

    var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }
}

// MARK: - G-AIRMET  GET /api/ops/gairmet?route=ORIGIN,DEST

/// Route-filtered G-AIRMET turbulence / wind-shear forecast. Same family as
/// TCF: Envelope D, `relevant[]` empty is the common quiet case, and it
/// never moves the verdict.
nonisolated struct GairmetEnvelope: Codable, Hashable, Sendable {
    let route: String?
    let relevantCount: Int?
    let relevant: [GairmetArea]?
    let riskLevel: String?
    let source: String?
    let timestamp: String?
    let summary: String?
    let error: String?
    let hazardsQueried: [String]?

    enum CodingKeys: String, CodingKey {
        case route, relevant, source, timestamp, summary, error
        case relevantCount = "relevant_count"
        case riskLevel = "risk_level"
        case hazardsQueried = "hazards_queried"
    }

    var areas: [GairmetArea] { relevant ?? [] }
    var level: String { (riskLevel ?? "NONE").uppercased() }
    var isQuiet: Bool { areas.isEmpty || level == "NONE" }

    var nearOriginCount: Int { areas.filter { $0.nearOrigin == true }.count }
    var nearDestCount: Int { areas.filter { $0.nearDest == true }.count }
    var alongRouteCount: Int { areas.filter { $0.alongRoute == true }.count }
}

nonisolated struct GairmetArea: Codable, Hashable, Sendable {
    let hazard: String?
    let severity: String?
    let base: String?
    let top: String?
    let baseFt: JSONValue?
    let topFt: JSONValue?
    let validFrom: String?
    let expires: String?
    let product: String?
    let nearOrigin: Bool?
    let nearDest: Bool?
    let alongRoute: Bool?

    enum CodingKeys: String, CodingKey {
        case hazard, severity, base, top, product, expires
        case baseFt = "base_ft"
        case topFt = "top_ft"
        case validFrom = "valid_from"
        case nearOrigin = "near_origin"
        case nearDest = "near_dest"
        case alongRoute = "along_route"
    }

    var severityCode: String { (severity ?? "").uppercased() }

    var hazardLabel: String {
        switch (hazard ?? "").uppercased() {
        case "TURB-HI", "TURB_HI", "TURBHI": return "High-altitude turbulence"
        case "TURB-LO", "TURB_LO", "TURBLO": return "Low-altitude turbulence"
        case "LLWS": return "Low-level wind shear"
        case "ICE": return "Icing"
        case "IFR": return "IFR conditions"
        case "MT-OBSC", "MT_OBSC": return "Mountain obscuration"
        case "SFC-WIND", "SFC_WIND": return "Strong surface wind"
        case "TURB": return "Turbulence"
        default: return hazard?.replacingOccurrences(of: "-", with: " ").capitalized ?? "Advisory"
        }
    }

    var severityLabel: String {
        switch severityCode {
        case "EXTM": return "Extreme"
        case "SEV": return "Severe"
        case "MOD": return "Moderate"
        case "LGT": return "Light"
        default: return severity?.capitalized ?? ""
        }
    }

    /// "FL180–FL410" / "SFC–FL180" from the hundreds-of-feet or raw fields.
    var altitudeBand: String? {
        let low = flightLevel(baseFt) ?? rawLevel(base)
        let high = flightLevel(topFt) ?? rawLevel(top)
        switch (low, high) {
        case let (low?, high?) where low != high: return "\(low)–\(high)"
        case let (low?, high?) : return low
        case let (low?, nil): return "from \(low)"
        case let (nil, high?): return "up to \(high)"
        default: return nil
        }
    }

    var whereText: String {
        if nearOrigin == true { return "near departure" }
        if nearDest == true { return "near arrival" }
        if alongRoute == true { return "along the route" }
        return "near the route"
    }

    private func flightLevel(_ value: JSONValue?) -> String? {
        guard let feet = value?.intValue, feet > 0 else { return nil }
        return "FL\(feet / 100)"
    }

    private func rawLevel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.uppercased() == "SFC" { return "SFC" }
        if let hundreds = Int(raw), hundreds > 0 { return "FL\(hundreds)" }
        return raw
    }
}

// MARK: - ATFM  GET /api/ops/atfm?flight=&date=

/// Eurocontrol CTOT / ATFM inference. Shown only when the destination is
/// in ECAC airspace and the server verdict is PROBABLE or POSSIBLE.
nonisolated struct AtfmEnvelope: Codable, Hashable, Sendable {
    let applicable: Bool?
    let destination: String?
    let inEurocontrol: Bool?
    let verdict: String?
    let confidencePct: JSONValue?
    let indicators: [AtfmIndicator]?
    let delayMin: JSONValue?
    let note: String?
    let error: String?
    let source: String?
    let flight: String?
    let route: String?
    let scheduledDeparture: String?
    let estimatedDeparture: String?

    enum CodingKeys: String, CodingKey {
        case applicable, destination, verdict, indicators, note, error, source, flight, route
        case inEurocontrol = "in_eurocontrol"
        case confidencePct = "confidence_pct"
        case delayMin = "delay_min"
        case scheduledDeparture = "scheduled_departure"
        case estimatedDeparture = "estimated_departure"
    }

    var verdictCode: String { (verdict ?? "").uppercased() }
    var isApplicable: Bool { applicable ?? false }

    /// Chip/card gate — UNLIKELY / NO_INDICATION / not-applicable stay hidden.
    var shouldDisplay: Bool {
        isApplicable && (verdictCode == "PROBABLE" || verdictCode == "POSSIBLE")
    }

    var delayMinutes: Int? { delayMin?.intValue }

    var headline: String {
        switch verdictCode {
        case "PROBABLE":
            return "Eurocontrol ATFM regulation looks probable — a CTOT slot may be holding this departure."
        case "POSSIBLE":
            return "Eurocontrol ATFM regulation is possible — watch for a CTOT (calculated take-off time)."
        default:
            return "No CTOT indication from the delay pattern."
        }
    }
}

nonisolated struct AtfmIndicator: Codable, Hashable, Sendable {
    let type: String?
    let detail: String?
    let weight: JSONValue?
}

// MARK: - ATC flow brief  GET /api/ops/flow-brief

/// Composed NAS flow picture: TFMS advisories, TBFM meter-fix ETAs, TFDM
/// taxi/queue, plus server `effects[]`. Decodes both the documented composed
/// shape and raw SWIM envelopes so the UI works before/after the backend PR.
nonisolated struct FlowBriefEnvelope: Codable, Hashable, Sendable {
    var flight: String?
    var date: String?
    var origin: String?
    var destination: String?
    var effects: [BriefEffect]?
    var advisories: [FlowAdvisory]?
    var meterFixes: [FlowMeterFix]?
    var tfdm: FlowTfdm?
    var summary: String?
    var error: String?
    var source: String?
    /// True when the composed `/api/ops/flow-brief` route itself 404'd and
    /// this payload was assembled from the individual SWIM helpers.
    var composedFromHelpers: Bool?

    enum CodingKeys: String, CodingKey {
        case flight, date, origin, destination, effects, advisories, summary, error, source
        case meterFixes = "meter_fixes"
        case tfdm
        case composedFromHelpers = "composed_from_helpers"
    }

    var orderedEffects: [BriefEffect] { effects ?? [] }

    var hasContent: Bool {
        !orderedEffects.isEmpty
            || !(advisories ?? []).isEmpty
            || !(meterFixes ?? []).isEmpty
            || (tfdm?.hasContent ?? false)
    }

    init(flight: String? = nil, date: String? = nil, origin: String? = nil,
         destination: String? = nil, effects: [BriefEffect]? = nil,
         advisories: [FlowAdvisory]? = nil, meterFixes: [FlowMeterFix]? = nil,
         tfdm: FlowTfdm? = nil, summary: String? = nil, error: String? = nil,
         source: String? = nil, composedFromHelpers: Bool? = nil) {
        self.flight = flight
        self.date = date
        self.origin = origin
        self.destination = destination
        self.effects = effects
        self.advisories = advisories
        self.meterFixes = meterFixes
        self.tfdm = tfdm
        self.summary = summary
        self.error = error
        self.source = source
        self.composedFromHelpers = composedFromHelpers
    }

    /// Tolerant parse from whatever the server (or a SWIM helper) sent.
    static func parse(_ json: JSONValue) -> FlowBriefEnvelope {
        var envelope = FlowBriefEnvelope()
        envelope.flight = json["flight"]?.stringValue
        envelope.date = json["date"]?.stringValue
        envelope.origin = json["origin"]?.stringValue ?? json["origin_icao"]?.stringValue
        envelope.destination = json["destination"]?.stringValue ?? json["dest"]?.stringValue
            ?? json["destination_icao"]?.stringValue
        envelope.summary = json["summary"]?.stringValue
        envelope.error = json["error"]?.stringValue
        envelope.source = json["source"]?.stringValue
        envelope.effects = parseEffects(json["effects"])
        envelope.advisories = parseAdvisories(
            json["advisories"]
            ?? json["tfms"]?["advisories"]
            ?? json["tfms"]?["results"]
            ?? json["tfms_flow"]?["results"]
            ?? json["tfms_flow"])
        envelope.meterFixes = parseMeterFixes(
            json["meter_fixes"]
            ?? json["tbfm"]?["meter_fixes"]
            ?? json["tbfm"]?["etas"]
            ?? json["tbfm"]?["results"]
            ?? json["tbfm"])
        envelope.tfdm = parseTfdm(
            json["tfdm"]
            ?? json["surface"])
        return envelope
    }

    /// Build a flow brief from the individual SWIM helpers when
    /// `/api/ops/flow-brief` is not deployed yet.
    static func compose(tfms: SwimEnvelope?, tbfm: SwimEnvelope?,
                        tfdm: SwimEnvelope?, flight: String?,
                        origin: String?, dest: String?) -> FlowBriefEnvelope {
        var envelope = FlowBriefEnvelope(
            flight: flight, origin: origin, destination: dest,
            source: "swim-helpers", composedFromHelpers: true)
        if let results = tfms?.results {
            envelope.advisories = parseAdvisories(.array(results))
        }
        if let results = tbfm?.results {
            envelope.meterFixes = parseMeterFixes(.array(results))
        }
        if let tfdm {
            envelope.tfdm = parseTfdmFromSwim(tfdm, airport: origin)
        }
        if let tfmsError = tfms?.error, envelope.advisories?.isEmpty ?? true {
            envelope.error = tfmsError
        }
        return envelope
    }

    private static func parseEffects(_ value: JSONValue?) -> [BriefEffect]? {
        guard let items = value?.arrayValue else { return nil }
        let data = (try? JSONEncoder().encode(items))
            .flatMap { try? JSONDecoder().decode([BriefEffect].self, from: $0) }
        return data
    }

    static func parseAdvisories(_ value: JSONValue?) -> [FlowAdvisory]? {
        let items = value?.arrayValue ?? []
        let parsed = items.compactMap(FlowAdvisory.init(json:))
        return parsed.isEmpty ? nil : parsed
    }

    static func parseMeterFixes(_ value: JSONValue?) -> [FlowMeterFix]? {
        let items = value?.arrayValue ?? []
        let parsed = items.compactMap(FlowMeterFix.init(json:))
        return parsed.isEmpty ? nil : parsed
    }

    static func parseTfdm(_ value: JSONValue?) -> FlowTfdm? {
        guard let value, value.objectValue != nil || value.arrayValue != nil else { return nil }
        if let array = value.arrayValue {
            return parseTfdmFromResults(array)
        }
        if let results = value["results"]?.arrayValue {
            return parseTfdmFromResults(results) ?? FlowTfdm(json: value)
        }
        return FlowTfdm(json: value)
    }

    private static func parseTfdmFromSwim(_ swim: SwimEnvelope, airport: String?) -> FlowTfdm? {
        if let results = swim.results, let parsed = parseTfdmFromResults(results) {
            return parsed
        }
        if swim.isQuiet {
            return FlowTfdm(supported: false, airport: airport,
                            note: "No TFDM surface messages in the capture window — JFK and LGA are not in TFDM yet.")
        }
        if let error = swim.error {
            return FlowTfdm(supported: false, airport: airport, note: error)
        }
        return nil
    }

    private static func parseTfdmFromResults(_ results: [JSONValue]) -> FlowTfdm? {
        let records = results.compactMap(FlowTfdm.init(json:)).filter(\.hasContent)
        return records.first
    }
}

nonisolated struct FlowAdvisory: Codable, Hashable, Sendable {
    let type: String?
    let title: String?
    let text: String?
    let plainEnglish: String?
    let advisoryNumber: String?
    let effectiveStart: String?
    let effectiveEnd: String?

    enum CodingKeys: String, CodingKey {
        case type, title, text
        case plainEnglish = "plain_english"
        case advisoryNumber = "advisory_number"
        case effectiveStart = "effective_start"
        case effectiveEnd = "effective_end"
    }

    init(type: String?, title: String?, text: String?, plainEnglish: String?,
         advisoryNumber: String?, effectiveStart: String?, effectiveEnd: String?) {
        self.type = type
        self.title = title
        self.text = text
        self.plainEnglish = plainEnglish
        self.advisoryNumber = advisoryNumber
        self.effectiveStart = effectiveStart
        self.effectiveEnd = effectiveEnd
    }

    init?(json: JSONValue) {
        let type = json["type"]?.stringValue
        let title = json["title"]?.stringValue
        let text = json["text"]?.stringValue ?? json["advisory_text"]?.stringValue
        let plain = json["plain_english"]?.stringValue ?? json["plainEnglish"]?.stringValue
        guard title != nil || text != nil || plain != nil else { return nil }
        // Restriction / TMI rows without prose are noise for travellers.
        if title == nil && plain == nil, (text ?? "").count < 8 { return nil }
        self.init(type: type, title: title, text: text, plainEnglish: plain,
                  advisoryNumber: json["advisory_number"]?.stringValue,
                  effectiveStart: json["effective_start"]?.stringValue,
                  effectiveEnd: json["effective_end"]?.stringValue)
    }

    /// Server-written plain English when present; otherwise the title, then
    /// a trimmed first sentence of the raw advisory text.
    var displayLine: String {
        if let plainEnglish, !plainEnglish.isEmpty { return plainEnglish }
        if let title, !title.isEmpty { return title }
        if let text, !text.isEmpty {
            let trimmed = text.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let period = trimmed.firstIndex(of: "."),
               trimmed.distance(from: trimmed.startIndex, to: period) < 180 {
                return String(trimmed[...period])
            }
            return String(trimmed.prefix(160))
        }
        return "TFMS flow advisory"
    }

    var windowText: String? {
        let start = TimeFmt.clock(effectiveStart)
        let end = TimeFmt.clock(effectiveEnd)
        if start == "—" && end == "—" { return nil }
        if end == "—" { return "from \(start)" }
        if start == "—" { return "until \(end)" }
        return "\(start)–\(end)"
    }
}

nonisolated struct FlowMeterFix: Codable, Hashable, Sendable {
    let flightId: String?
    let fix: String?
    let eta: String?
    let sta: String?
    let localDisplay: String?
    let destAirport: String?

    enum CodingKeys: String, CodingKey {
        case fix, eta, sta
        case flightId = "flight_id"
        case localDisplay = "local_display"
        case destAirport = "dest_airport"
    }

    init(flightId: String?, fix: String?, eta: String?, sta: String?,
         localDisplay: String?, destAirport: String?) {
        self.flightId = flightId
        self.fix = fix
        self.eta = eta
        self.sta = sta
        self.localDisplay = localDisplay
        self.destAirport = destAirport
    }

    init?(json: JSONValue) {
        let etaBlock = json["eta"]
        let info = json["flight_info"]
        let flightId = json["flight_id"]?.stringValue ?? json["flight"]?.stringValue
            ?? info?["acid"]?.stringValue
        let fix = json["fix"]?.stringValue ?? json["meter_fix"]?.stringValue
            ?? etaBlock?["meterFix"]?.stringValue ?? etaBlock?["fix"]?.stringValue
            ?? info?["meterFix"]?.stringValue ?? info?["fix"]?.stringValue
        let eta = json["eta"]?.stringValue
            ?? etaBlock?["eta"]?.stringValue ?? etaBlock?["time"]?.stringValue
            ?? etaBlock?["crossingTime"]?.stringValue
        let sta = json["sta"]?.stringValue ?? etaBlock?["sta"]?.stringValue
            ?? etaBlock?["scheduledTime"]?.stringValue
        let local = json["local_display"]?.stringValue ?? json["eta_local"]?.stringValue
        guard fix != nil || eta != nil || sta != nil || local != nil else { return nil }
        self.init(flightId: flightId, fix: fix, eta: eta, sta: sta,
                  localDisplay: local, destAirport: json["dest_airport"]?.stringValue)
    }

    var timeText: String {
        if let localDisplay, !localDisplay.isEmpty { return localDisplay }
        if let eta, TimeFmt.parseISO(eta) != nil { return TimeFmt.clock(eta) }
        if let sta, TimeFmt.parseISO(sta) != nil { return TimeFmt.clock(sta) }
        return eta ?? sta ?? "—"
    }

    var headline: String {
        if let fix, !fix.isEmpty {
            return "Meter fix \(fix) · \(timeText)"
        }
        return "Metered arrival · \(timeText)"
    }
}

nonisolated struct FlowTfdm: Codable, Hashable, Sendable {
    let supported: Bool?
    let airport: String?
    let flightState: String?
    let taxiOutMinutes: JSONValue?
    let queueWaitMinutes: JSONValue?
    let earliestWheelsUp: String?
    let estimatedWheelsUp: String?
    let runwayAssigned: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case supported, airport, note
        case flightState = "flight_state"
        case taxiOutMinutes = "taxi_out_minutes"
        case queueWaitMinutes = "queue_wait_minutes"
        case earliestWheelsUp = "earliest_wheels_up"
        case estimatedWheelsUp = "estimated_wheels_up"
        case runwayAssigned = "runway_assigned"
    }

    init(supported: Bool? = nil, airport: String? = nil, flightState: String? = nil,
         taxiOutMinutes: JSONValue? = nil, queueWaitMinutes: JSONValue? = nil,
         earliestWheelsUp: String? = nil, estimatedWheelsUp: String? = nil,
         runwayAssigned: String? = nil, note: String? = nil) {
        self.supported = supported
        self.airport = airport
        self.flightState = flightState
        self.taxiOutMinutes = taxiOutMinutes
        self.queueWaitMinutes = queueWaitMinutes
        self.earliestWheelsUp = earliestWheelsUp
        self.estimatedWheelsUp = estimatedWheelsUp
        self.runwayAssigned = runwayAssigned
        self.note = note
    }

    init?(json: JSONValue) {
        let taxi = json["taxi_out_minutes"]
        let queue = json["queue_wait_minutes"]
        let earliest = json["earliest_wheels_up"]?.stringValue
            ?? json["runway_departure_earliest"]?.stringValue
        let estimated = json["estimated_wheels_up"]?.stringValue
            ?? json["runway_departure_estimated"]?.stringValue
        let runway = json["runway_assigned"]?.stringValue ?? json["runway"]?.stringValue
        let state = json["flight_state"]?.stringValue
        let note = json["note"]?.stringValue
        let supported = json["supported"]?.boolValue
        let airport = json["airport"]?.stringValue
        let hasNumbers = taxi?.intValue != nil || queue?.intValue != nil
        let hasTimes = earliest != nil || estimated != nil
        guard hasNumbers || hasTimes || runway != nil || state != nil || note != nil || supported != nil else {
            return nil
        }
        self.init(supported: supported ?? (hasNumbers || hasTimes),
                  airport: airport, flightState: state,
                  taxiOutMinutes: taxi, queueWaitMinutes: queue,
                  earliestWheelsUp: earliest, estimatedWheelsUp: estimated,
                  runwayAssigned: runway, note: note)
    }

    var hasContent: Bool {
        taxiOutMinutes?.intValue != nil
            || queueWaitMinutes?.intValue != nil
            || earliestWheelsUp != nil
            || estimatedWheelsUp != nil
            || runwayAssigned != nil
            || !(note ?? "").isEmpty
    }

    var wheelsUpText: String? {
        if let earliestWheelsUp { return TimeFmt.clock(earliestWheelsUp) }
        if let estimatedWheelsUp { return TimeFmt.clock(estimatedWheelsUp) }
        return nil
    }
}

// MARK: - ITWS helpers

/// One ITWS terminal-weather alert (microburst / gust front / wind shear).
nonisolated struct ItwsAlert: Hashable, Sendable {
    let airport: String?
    let kind: String
    let headline: String
    let detail: String?

    var kindCode: String { kind.uppercased() }

    static func parse(from envelope: SwimEnvelope?) -> [ItwsAlert] {
        guard let results = envelope?.results else { return [] }
        return results.compactMap { item in
            let kind = (item["alert_type"]?.stringValue
                        ?? item["product_name"]?.stringValue
                        ?? item["type"]?.stringValue
                        ?? "").uppercased()
            let mapped: String
            if kind.contains("MICROBURST") || kind.contains("MB") && kind.contains("ALERT") {
                mapped = "MICROBURST"
            } else if kind.contains("GUST") {
                mapped = "GUST_FRONT"
            } else if kind.contains("SHEAR") || kind.contains("WS") {
                mapped = "WIND_SHEAR"
            } else if kind.contains("STORM") {
                mapped = "STORM"
            } else {
                return nil
            }
            let airport = item["airport"]?.stringValue
            let minutes = item["gust_front"]?["minutes_to_impact"]?.stringValue
                ?? item["gust_front"]?["minutes_to_impact"]?.intValue.map(String.init)
            let headline: String
            switch mapped {
            case "MICROBURST":
                headline = "Microburst alert"
            case "GUST_FRONT":
                if let minutes {
                    headline = "Gust front — impact in \(minutes) min"
                } else {
                    headline = "Gust front"
                }
            case "WIND_SHEAR":
                headline = "Wind shear alert"
            default:
                headline = "Terminal storm cell"
            }
            return ItwsAlert(airport: airport, kind: mapped, headline: headline,
                             detail: item["product_name"]?.stringValue)
        }
    }
}

// MARK: - Open-Meteo / extended weather  (optional)

/// Model-guidance strip. Hidden when the endpoint is absent or empty.
/// Explicitly not a verdict driver — labelled as such in the UI.
nonisolated struct ModelGuidanceEnvelope: Codable, Hashable, Sendable {
    var source: String?
    var model: String?
    var note: String?
    var airports: [ModelGuidanceAirport]
    var fetchedAt: String?

    var hasContent: Bool { airports.contains { $0.hasContent } }

    init(source: String? = nil, model: String? = nil, note: String? = nil,
         airports: [ModelGuidanceAirport] = [], fetchedAt: String? = nil) {
        self.source = source
        self.model = model
        self.note = note
        self.airports = airports
        self.fetchedAt = fetchedAt
    }

    static func parse(_ json: JSONValue, icaos: [String] = []) -> ModelGuidanceEnvelope {
        var envelope = ModelGuidanceEnvelope()
        envelope.source = json["source"]?.stringValue ?? json["provider"]?.stringValue
        envelope.model = json["model"]?.stringValue ?? json["model_name"]?.stringValue
        envelope.note = json["note"]?.stringValue
        envelope.fetchedAt = json["timestamp"]?.stringValue ?? json["valid_time"]?.stringValue

        if let object = json["airports"]?.objectValue {
            envelope.airports = object.keys.sorted().compactMap { key in
                object[key].map { ModelGuidanceAirport(icao: key, json: $0) }
            }
        } else if let object = json["data"]?.objectValue {
            envelope.airports = object.keys.sorted().compactMap { key in
                object[key].map { ModelGuidanceAirport(icao: key, json: $0) }
            }
        } else if json["temperature_c"] != nil || json["hourly"] != nil
                    || json["current"] != nil || json["wind_speed_kts"] != nil {
            let icao = icaos.first ?? json["icao"]?.stringValue ?? json["airport"]?.stringValue
            envelope.airports = [ModelGuidanceAirport(icao: icao, json: json)]
        }
        envelope.airports = envelope.airports.filter(\.hasContent)
        return envelope
    }
}

nonisolated struct ModelGuidanceAirport: Codable, Hashable, Sendable {
    var icao: String?
    var temperatureC: Double?
    var windKts: Double?
    var gustKts: Double?
    var windDirectionDeg: String?
    var precipitationMm: Double?
    var cloudCoverPct: Double?
    var visibilityM: Double?
    var validTime: String?
    var summary: String?

    var hasContent: Bool {
        temperatureC != nil || windKts != nil || precipitationMm != nil
            || cloudCoverPct != nil || visibilityM != nil || !(summary ?? "").isEmpty
    }

    init(icao: String?, json: JSONValue) {
        self.icao = icao ?? json["icao"]?.stringValue ?? json["airport"]?.stringValue
        let current = json["current"] ?? json
        let hourly = json["hourly"]
        temperatureC = current["temperature_c"]?.doubleValue
            ?? current["temperature_2m"]?.doubleValue
            ?? hourly?["temperature_2m"]?.arrayValue?.first?.doubleValue
        windKts = current["wind_speed_kts"]?.doubleValue
            ?? current["wind_kts"]?.doubleValue
            ?? knots(fromMps: current["wind_speed_10m"]?.doubleValue)
            ?? knots(fromMps: hourly?["wind_speed_10m"]?.arrayValue?.first?.doubleValue)
        gustKts = current["wind_gusts_kts"]?.doubleValue
            ?? current["gust_kts"]?.doubleValue
            ?? knots(fromMps: current["wind_gusts_10m"]?.doubleValue)
        windDirectionDeg = current["wind_direction_deg"]?.stringValue
            ?? current["wind_direction_10m"]?.stringValue
        precipitationMm = current["precipitation_mm"]?.doubleValue
            ?? current["precipitation"]?.doubleValue
            ?? hourly?["precipitation"]?.arrayValue?.first?.doubleValue
        cloudCoverPct = current["cloud_cover_pct"]?.doubleValue
            ?? current["cloud_cover"]?.doubleValue
            ?? hourly?["cloud_cover"]?.arrayValue?.first?.doubleValue
        visibilityM = current["visibility_m"]?.doubleValue
            ?? current["visibility"]?.doubleValue
        validTime = current["valid_time"]?.stringValue
            ?? current["time"]?.stringValue
            ?? hourly?["time"]?.arrayValue?.first?.stringValue
        summary = current["summary"]?.stringValue ?? json["summary"]?.stringValue
    }

    var line: String {
        var parts: [String] = []
        if let temperatureC { parts.append("\(Int(temperatureC.rounded()))°C") }
        if let windKts {
            var wind = "Wind \(Int(windKts.rounded())) kt"
            if let gustKts, gustKts > windKts { wind += " g\(Int(gustKts.rounded()))" }
            parts.append(wind)
        }
        if let precipitationMm, precipitationMm > 0 {
            parts.append(String(format: "%.1f mm precip", precipitationMm))
        }
        if let cloudCoverPct { parts.append("Clouds \(Int(cloudCoverPct.rounded()))%") }
        if let visibilityM, visibilityM > 0 {
            let sm = visibilityM / 1609.34
            parts.append(sm >= 10 ? "Vis 10+ sm" : String(format: "Vis %.1f sm", sm))
        }
        if let summary, !summary.isEmpty { parts.append(summary) }
        return parts.isEmpty ? "No model fields" : parts.joined(separator: " · ")
    }

    private func knots(fromMps mps: Double?) -> Double? {
        guard let mps else { return nil }
        return mps * 1.94384
    }
}

// MARK: - Filed route (display-only, never bought)

extension JSONValue {
    /// Best-effort filed-route string from a status `data.route` object or
    /// brief `llm_payload.facts`. Never triggers a paid route query.
    var filedRouteString: String? {
        if case .string(let value) = self, !value.isEmpty { return value }
        if let value = self["route"]?.stringValue, !value.isEmpty { return value }
        if let value = self["filed_route"]?.stringValue, !value.isEmpty { return value }
        if let value = self["route_string"]?.stringValue, !value.isEmpty { return value }
        if let fixes = self["waypoints"]?.arrayValue {
            let names = fixes.compactMap {
                $0.stringValue ?? $0["name"]?.stringValue ?? $0["ident"]?.stringValue
                    ?? $0["fix"]?.stringValue
            }
            if !names.isEmpty { return names.joined(separator: " ") }
        }
        return nil
    }
}
