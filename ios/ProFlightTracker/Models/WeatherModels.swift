import Foundation

/// Wind group shared by METAR and TAF. Direction may be numeric or "VRB".
nonisolated struct WindInfo: Codable, Hashable, Sendable {
    let directionDeg: JSONValue?
    let speedKts: Double?
    let gustKts: Double?

    enum CodingKeys: String, CodingKey {
        case directionDeg = "direction_deg"
        case speedKts = "speed_kts"
        case gustKts = "gust_kts"
    }

    var summary: String? {
        guard let speed = speedKts else { return nil }
        let dir = directionDeg?.stringValue ?? "—"
        var text = "\(dir)° at \(Int(speed)) kt"
        if dir == "VRB" { text = "Variable at \(Int(speed)) kt" }
        if let gust = gustKts { text += ", gusting \(Int(gust))" }
        return text
    }
}

nonisolated struct CloudLayer: Codable, Hashable, Sendable {
    let coverage: String?
    let baseAglFt: Double?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case coverage
        case baseAglFt = "base_agl_ft"
        case type
    }
}

/// One decoded METAR observation keyed by ICAO in the envelope.
nonisolated struct MetarObservation: Codable, Hashable, Sendable {
    let raw: String?
    let observationTime: String?
    let wind: WindInfo?
    let visibilitySm: String?
    let ceilingFt: Double?
    let clouds: [CloudLayer]?
    let temperatureC: Double?
    let dewpointC: Double?
    let altimeterMb: Double?
    let flightCategory: String?
    let weatherPhenomena: String?

    enum CodingKeys: String, CodingKey {
        case raw
        case observationTime = "observation_time"
        case wind
        case visibilitySm = "visibility_sm"
        case ceilingFt = "ceiling_ft"
        case clouds
        case temperatureC = "temperature_c"
        case dewpointC = "dewpoint_c"
        case altimeterMb = "altimeter_mb"
        case flightCategory = "flight_category"
        case weatherPhenomena = "weather_phenomena"
    }

    /// Plain-English one-liner decode of the observation.
    var decoded: String {
        var parts: [String] = []
        if let wind = wind?.summary { parts.append("Wind \(wind)") }
        if let vis = visibilitySm { parts.append("Visibility \(vis) sm") }
        if let ceiling = ceilingFt { parts.append("Ceiling \(Int(ceiling)) ft") }
        if let wx = weatherPhenomena, !wx.isEmpty { parts.append(wx) }
        if let temp = temperatureC { parts.append("\(Int(temp))°C") }
        return parts.isEmpty ? "No details available" : parts.joined(separator: " · ")
    }
}

/// GET /api/weather/metar
nonisolated struct MetarEnvelope: Codable, Sendable {
    let pullTime: String?
    let command: String?
    let data: [String: MetarObservation]?
    let errors: [String]?

    enum CodingKeys: String, CodingKey {
        case pullTime = "pull_time"
        case command, data, errors
    }
}

nonisolated struct TafPeriod: Codable, Hashable, Sendable {
    let timeFrom: String?
    let timeTo: String?
    let changeIndicator: String?
    let probability: JSONValue?
    let wind: WindInfo?
    let visibilitySm: String?
    let ceilingFt: Double?
    let weather: String?

    enum CodingKeys: String, CodingKey {
        case timeFrom = "time_from"
        case timeTo = "time_to"
        case changeIndicator = "change_indicator"
        case probability, wind
        case visibilitySm = "visibility_sm"
        case ceilingFt = "ceiling_ft"
        case weather
    }
}

/// One TAF terminal forecast keyed by ICAO in the envelope.
nonisolated struct TafReport: Codable, Hashable, Sendable {
    let raw: String?
    let issueTime: String?
    let validFrom: String?
    let validTo: String?
    let forecastPeriods: [TafPeriod]?

    enum CodingKeys: String, CodingKey {
        case raw
        case issueTime = "issue_time"
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case forecastPeriods = "forecast_periods"
    }
}

/// GET /api/weather/taf
nonisolated struct TafEnvelope: Codable, Sendable {
    let pullTime: String?
    let command: String?
    let data: [String: TafReport]?
    let errors: [String]?
    let coverageGaps: [String]?

    enum CodingKeys: String, CodingKey {
        case pullTime = "pull_time"
        case command, data, errors
        case coverageGaps = "coverage_gaps"
    }
}

/// Per-airport FAA delay-program record, keyed by ICAO in the envelope.
nonisolated struct FaaAirportStatus: Codable, Hashable, Sendable {
    let groundDelayPrograms: [JSONValue]?
    let groundStops: [JSONValue]?
    let arrivalDepartureDelays: [JSONValue]?
    let closures: [JSONValue]?
    let status: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case groundDelayPrograms = "ground_delay_programs"
        case groundStops = "ground_stops"
        case arrivalDepartureDelays = "arrival_departure_delays"
        case closures, status, source
    }

    var hasAnyProgram: Bool {
        !(groundStops ?? []).isEmpty
            || !(groundDelayPrograms ?? []).isEmpty
            || !(arrivalDepartureDelays ?? []).isEmpty
            || !(closures ?? []).isEmpty
    }
}

extension FaaAirportStatus {
    /// Compact human summary of the first GDP record, e.g. "avg 2h07m".
    var gdpDelaySummary: String? {
        guard let gdp = groundDelayPrograms?.first else { return nil }
        if let avg = Self.compactDelay(gdp["average_delay"]?.stringValue ?? gdp["avg_delay"]?.stringValue) {
            return "avg \(avg)"
        }
        if let max = Self.compactDelay(gdp["max_delay"]?.stringValue) {
            return "up to \(max)"
        }
        return nil
    }

    /// Compact delay range from the first arrival/departure delay record, e.g. "31m–45m".
    var delayRangeText: String? {
        guard let delay = arrivalDepartureDelays?.first else { return nil }
        let minText = Self.compactDelay(delay["min_delay"]?.stringValue)
        let maxText = Self.compactDelay(delay["max_delay"]?.stringValue)
        switch (minText, maxText) {
        case let (low?, high?): return low == high ? low : "\(low)–\(high)"
        case let (low?, nil): return low
        case let (nil, high?): return "up to \(high)"
        default: return nil
        }
    }

    /// Normalized trend from the first delay record: "increasing", "decreasing", or nil.
    var delayTrend: String? {
        guard let trend = arrivalDepartureDelays?.first?["trend"]?.stringValue?.lowercased() else { return nil }
        if trend.contains("incr") || trend.contains("up") { return "increasing" }
        if trend.contains("decr") || trend.contains("down") { return "decreasing" }
        return nil
    }

    /// Delay range with a trend arrow appended, for compact chips: "31m–45m ↑".
    var delayChipText: String? {
        guard let range = delayRangeText else { return nil }
        switch delayTrend {
        case "increasing": return "\(range) ↑"
        case "decreasing": return "\(range) ↓"
        default: return range
        }
    }

    /// Compresses FAA delay phrasing ("2 hours and 7 minutes", "31 minutes",
    /// "1:45", bare minute counts) into "2h07m" / "31m" style.
    static func compactDelay(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        let colonParts = text.split(separator: ":")
        if colonParts.count == 2,
           let hours = Int(colonParts[0].trimmingCharacters(in: .whitespaces)),
           let minutes = Int(colonParts[1].prefix(2).trimmingCharacters(in: .whitespaces)) {
            return formatDelay(totalMinutes: hours * 60 + minutes)
        }

        var totalMinutes = 0
        var pendingNumber: Int?
        var pendingDigits = ""
        var pendingUnit = ""

        func flushToken() {
            if !pendingDigits.isEmpty, let value = Int(pendingDigits) {
                applyPending()
                pendingNumber = value
            }
            if !pendingUnit.isEmpty {
                if let value = pendingNumber {
                    if pendingUnit.hasPrefix("h") {
                        totalMinutes += value * 60
                    } else if pendingUnit.hasPrefix("m") {
                        totalMinutes += value
                    }
                    if pendingUnit.hasPrefix("h") || pendingUnit.hasPrefix("m") {
                        pendingNumber = nil
                    }
                }
            }
            pendingDigits = ""
            pendingUnit = ""
        }

        func applyPending() {
            if let value = pendingNumber {
                totalMinutes += value
                pendingNumber = nil
            }
        }

        for character in text {
            if character.isNumber {
                if !pendingUnit.isEmpty { flushToken() }
                pendingDigits.append(character)
            } else if character.isLetter {
                if !pendingDigits.isEmpty, pendingUnit.isEmpty { flushToken() }
                pendingUnit.append(character)
            } else {
                flushToken()
            }
        }
        flushToken()
        applyPending()

        guard totalMinutes > 0 else { return nil }
        return formatDelay(totalMinutes: totalMinutes)
    }

    private static func formatDelay(totalMinutes: Int) -> String? {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h\(String(format: "%02d", minutes))m" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return nil
    }
}

/// GET /api/weather/faa-status
nonisolated struct FaaStatusEnvelope: Codable, Sendable {
    let pullTime: String?
    let command: String?
    let data: [String: FaaAirportStatus]?
    let errors: [String]?

    enum CodingKeys: String, CodingKey {
        case pullTime = "pull_time"
        case command, data, errors
    }
}

/// GET /api/ops/tcf?route=ORIGIN,DEST — the FAA's TFM Convective Forecast,
/// the same polygon product traffic management uses to call ground stops and
/// reroutes 2–6h out. Sharper than reading "TS" from a TAF because it's the
/// input to the FAA response. Does NOT move the verdict — reference only.
nonisolated struct TcfEnvelope: Codable, Hashable, Sendable {
    let route: String?
    let issueTime: String?
    let relevantCount: Int?
    let relevant: [TcfArea]?
    let riskLevel: String?
    let source: String?
    let timestamp: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case route, relevant, source, timestamp, error
        case issueTime = "issue_time"
        case relevantCount = "relevant_count"
        case riskLevel = "risk_level"
    }

    /// MODERATE when any relevant area has medium coverage, LOW for sparse,
    /// NONE when nothing intersects the route. An empty list is the common
    /// case, not a failure.
    var level: String { (riskLevel ?? "NONE").uppercased() }
    var areas: [TcfArea] { relevant ?? [] }
    var isQuiet: Bool { areas.isEmpty || level == "NONE" }

    var nearOriginCount: Int { areas.filter { $0.nearOrigin == true }.count }
    var nearDestCount: Int { areas.filter { $0.nearDest == true }.count }
    var alongRouteCount: Int { areas.filter { $0.alongRoute == true }.count }

    /// Highest cloud tops across relevant areas, in hundreds of feet.
    var maxTopsHundredsFt: Int? {
        areas.compactMap(\.topsHundreds).max()
    }
}

/// One convective polygon that intersects the route. `tops_hundreds_ft` comes
/// back as either a number or a string depending on the upstream product.
nonisolated struct TcfArea: Codable, Hashable, Sendable {
    let validTime: String?
    let issueTime: String?
    let coverage: String?
    let confidence: String?
    let topsHundredsFt: JSONValue?
    let nearOrigin: Bool?
    let nearDest: Bool?
    let alongRoute: Bool?

    enum CodingKeys: String, CodingKey {
        case coverage, confidence
        case validTime = "valid_time"
        case issueTime = "issue_time"
        case topsHundredsFt = "tops_hundreds_ft"
        case nearOrigin = "near_origin"
        case nearDest = "near_dest"
        case alongRoute = "along_route"
    }

    var topsHundreds: Int? { topsHundredsFt?.intValue }

    /// "39,000 ft tops" from the hundreds-of-feet field.
    var topsText: String? {
        guard let tops = topsHundreds else { return nil }
        return "tops \(tops * 100) ft"
    }

    /// TCF valid times arrive as "20260817_1100" (UTC).
    var validDate: Date? {
        guard let validTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: validTime)
    }

    var whereText: String {
        if nearOrigin == true { return "near departure" }
        if nearDest == true { return "near arrival" }
        if alongRoute == true { return "en route" }
        return "near the route"
    }
}

/// One international SIGMET from /api/weather/isigmet — everywhere the CONUS
/// `sigmet` feed doesn't reach (Alaska, Pacific, and every non-US FIR).
/// Only fetched when the route leaves CONUS.
nonisolated struct InternationalSigmet: Codable, Hashable, Sendable {
    let id: String?
    let issuingOffice: String?
    let firId: String?
    let firName: String?
    let hazard: String?
    let qualifier: String?
    let baseFt: Double?
    let topFt: Double?
    let validFrom: String?
    let validTo: String?

    enum CodingKeys: String, CodingKey {
        case id, hazard, qualifier
        case issuingOffice = "issuing_office"
        case firId = "fir_id"
        case firName = "fir_name"
        case baseFt = "base_ft"
        case topFt = "top_ft"
        case validFrom = "valid_from"
        case validTo = "valid_to"
    }

    /// "Occasional severe turbulence" style headline from hazard + qualifier.
    var headline: String {
        let hazardText: String
        switch (hazard ?? "").uppercased() {
        case "TURB": hazardText = "Turbulence"
        case "ICE": hazardText = "Icing"
        case "TS", "TSGR": hazardText = "Thunderstorms"
        case "MTW": hazardText = "Mountain wave"
        case "VA": hazardText = "Volcanic ash"
        case "DS", "SS": hazardText = "Dust or sandstorm"
        case "TC": hazardText = "Tropical cyclone"
        default: hazardText = hazard ?? "Hazard"
        }
        guard let qualifier, !qualifier.isEmpty else { return hazardText }
        let qualifierText = qualifier.uppercased() == "OCNL" ? "Occasional" :
            qualifier.uppercased() == "ISOL" ? "Isolated" :
            qualifier.uppercased() == "FRQ" ? "Frequent" : qualifier.capitalized
        return "\(qualifierText) \(hazardText.lowercased())"
    }

    /// "FL370–FL420" altitude band when the report carries one.
    var altitudeBand: String? {
        switch (baseFt, topFt) {
        case let (base?, top?): return "FL\(Int(base / 100))–FL\(Int(top / 100))"
        case let (nil, top?): return "up to FL\(Int(top / 100))"
        case let (base?, nil): return "from FL\(Int(base / 100))"
        default: return nil
        }
    }

    var firDisplay: String? {
        guard let name = firName, !name.isEmpty else { return firId }
        return name.capitalized
    }

    /// Coarse regional filter: keeps advisories whose FIR or issuing office
    /// shares an ICAO region prefix with either airport. This is a region
    /// match, NOT a route-intersection test — the UI says so, and nothing here
    /// feeds the verdict.
    static func inRegion(of icaos: [String], advisories: [InternationalSigmet]) -> [InternationalSigmet] {
        let codes = icaos.map { $0.uppercased() }.filter { $0.count >= 2 }
        guard !codes.isEmpty else { return [] }
        let twoChar = Set(codes.map { String($0.prefix(2)) })
        let oneChar = Set(codes.map { String($0.prefix(1)) })

        func prefixes(_ advisory: InternationalSigmet) -> [String] {
            [advisory.firId, advisory.issuingOffice]
                .compactMap { $0?.uppercased() }
                .filter { !$0.isEmpty }
        }

        let exact = advisories.filter { advisory in
            prefixes(advisory).contains { twoChar.contains(String($0.prefix(2))) }
        }
        if !exact.isEmpty { return exact }
        return advisories.filter { advisory in
            prefixes(advisory).contains { oneChar.contains(String($0.prefix(1))) }
        }
    }
}

/// GET /api/ops/lightning — live strikes near an airport.
nonisolated struct LightningEnvelope: Codable, Sendable {
    let airport: String?
    let searchRadiusNm: Double?
    let totalStrikes: Int?
    let strikesWithin5nm: Int?
    let rampClosureRisk: String?
    let activityLevel: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case airport
        case searchRadiusNm = "search_radius_nm"
        case totalStrikes = "total_strikes"
        case strikesWithin5nm = "strikes_within_5nm"
        case rampClosureRisk = "ramp_closure_risk"
        case activityLevel = "activity_level"
        case error
    }
}
