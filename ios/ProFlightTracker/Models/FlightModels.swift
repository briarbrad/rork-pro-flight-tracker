import Foundation

/// Per-source error entry attached to Envelope B responses.
nonisolated struct SourceError: Codable, Hashable, Sendable {
    let source: String?
    let error: String?
}

/// One flight leg as parsed from AeroAPI by the backend's flight_data.py.
nonisolated struct AeroFlight: Codable, Hashable, Sendable, Identifiable {
    var id: String { faFlightId ?? "\(ident ?? "?")_\(scheduledOut ?? "")" }

    let faFlightId: String?
    let ident: String?
    let operatorCode: String?
    let flightNumber: String?
    let registration: String?
    let aircraftType: String?
    let status: String?
    let originIcao: String?
    let originIata: String?
    let originName: String?
    let originCity: String?
    let destIcao: String?
    let destIata: String?
    let destName: String?
    let destCity: String?
    let scheduledOut: String?
    let estimatedOut: String?
    let actualOut: String?
    let scheduledOff: String?
    let estimatedOff: String?
    let actualOff: String?
    let scheduledOn: String?
    let estimatedOn: String?
    let actualOn: String?
    let scheduledIn: String?
    let estimatedIn: String?
    let actualIn: String?
    let gateOrigin: String?
    let gateDestination: String?
    let terminalOrigin: String?
    let terminalDestination: String?
    let inboundFaFlightId: String?
    let routeDistance: Double?
    let filedEte: Double?
    let progressPercent: Double?
    let blocked: Bool?
    let diverted: Bool?
    let cancelled: Bool?

    enum CodingKeys: String, CodingKey {
        case faFlightId = "fa_flight_id"
        case ident
        case operatorCode = "operator"
        case flightNumber = "flight_number"
        case registration
        case aircraftType = "aircraft_type"
        case status
        case originIcao = "origin_icao"
        case originIata = "origin_iata"
        case originName = "origin_name"
        case originCity = "origin_city"
        case destIcao = "dest_icao"
        case destIata = "dest_iata"
        case destName = "dest_name"
        case destCity = "dest_city"
        case scheduledOut = "scheduled_out"
        case estimatedOut = "estimated_out"
        case actualOut = "actual_out"
        case scheduledOff = "scheduled_off"
        case estimatedOff = "estimated_off"
        case actualOff = "actual_off"
        case scheduledOn = "scheduled_on"
        case estimatedOn = "estimated_on"
        case actualOn = "actual_on"
        case scheduledIn = "scheduled_in"
        case estimatedIn = "estimated_in"
        case actualIn = "actual_in"
        case gateOrigin = "gate_origin"
        case gateDestination = "gate_destination"
        case terminalOrigin = "terminal_origin"
        case terminalDestination = "terminal_destination"
        case inboundFaFlightId = "inbound_fa_flight_id"
        case routeDistance = "route_distance"
        case filedEte = "filed_ete"
        case progressPercent = "progress_percent"
        case blocked, diverted, cancelled
    }

    /// Minutes the departure has slipped vs schedule (mirrors the backend logic).
    var departureSlipMinutes: Double? {
        TimeFmt.slipMinutes(scheduled: scheduledOut, actual: actualOut, estimated: estimatedOut)
    }

    /// Minutes the arrival has slipped vs schedule.
    var arrivalSlipMinutes: Double? {
        TimeFmt.slipMinutes(scheduled: scheduledIn, actual: actualIn, estimated: estimatedIn)
    }

    var originDisplay: String { originIata ?? originIcao ?? "???" }
    var destDisplay: String { destIata ?? destIcao ?? "???" }
}

/// Envelope B: GET /api/flight/status
nonisolated struct FlightStatusEnvelope: Codable, Sendable {
    let pullTime: String?
    let command: String?
    let flight: String?
    let date: String?
    let data: StatusData?
    let errors: [SourceError]?

    enum CodingKeys: String, CodingKey {
        case pullTime = "pull_time"
        case command, flight, date, data, errors
    }

    nonisolated struct StatusData: Codable, Sendable {
        let flights: [AeroFlight]?
        let route: JSONValue?
    }
}

/// Live aircraft position from ADS-B / OpenSky / AeroAPI fallback.
nonisolated struct AircraftPosition: Codable, Hashable, Sendable {
    let latitude: Double?
    let longitude: Double?
    let altitudeFt: Double?
    let groundspeedKts: Double?
    let heading: Double?
    let verticalRate: Double?
    let onGround: Bool?
    let registration: String?
    let aircraftType: String?
    let callsign: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case altitudeFt = "altitude_ft"
        case groundspeedKts = "groundspeed_kts"
        case heading
        case verticalRate = "vertical_rate"
        case onGround = "on_ground"
        case registration
        case aircraftType = "aircraft_type"
        case callsign, source
    }
}

/// Envelope B: GET /api/flight/track
nonisolated struct TrackEnvelope: Codable, Sendable {
    let pullTime: String?
    let source: String?
    let command: String?
    let data: AircraftPosition?
    let errors: [SourceError]?

    enum CodingKeys: String, CodingKey {
        case pullTime = "pull_time"
        case source, command, data, errors
    }
}

/// Turn-time sufficiency analysis computed by the backend.
nonisolated struct TurnAnalysis: Codable, Hashable, Sendable {
    let turnTimeAvailableMin: Double?
    let turnTimeRequiredMinMinimum: Double?
    let turnTimeRequiredMinStandard: Double?
    let aircraftCategory: String?
    let sufficient: Bool?
    let inboundEta: String?
    let outboundScheduledDeparture: String?
    let inboundIdent: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case turnTimeAvailableMin = "turn_time_available_min"
        case turnTimeRequiredMinMinimum = "turn_time_required_min_minimum"
        case turnTimeRequiredMinStandard = "turn_time_required_min_standard"
        case aircraftCategory = "aircraft_category"
        case sufficient
        case inboundEta = "inbound_eta"
        case outboundScheduledDeparture = "outbound_scheduled_departure"
        case inboundIdent = "inbound_ident"
        case note
    }
}

/// Equipment chain payload: where the actual airplane is right now.
nonisolated struct ChainData: Codable, Hashable, Sendable {
    let outboundFlight: AeroFlight?
    let inboundFlight: AeroFlight?
    let aircraftPosition: AircraftPosition?
    let tailNumber: String?
    let aircraftType: String?
    let aircraftCategory: String?
    let turnAnalysis: TurnAnalysis?

    enum CodingKeys: String, CodingKey {
        case outboundFlight = "outbound_flight"
        case inboundFlight = "inbound_flight"
        case aircraftPosition = "aircraft_position"
        case tailNumber = "tail_number"
        case aircraftType = "aircraft_type"
        case aircraftCategory = "aircraft_category"
        case turnAnalysis = "turn_analysis"
    }
}

/// Envelope B: GET /api/flight/chain
nonisolated struct ChainEnvelope: Codable, Sendable {
    let pullTime: String?
    let command: String?
    let flight: String?
    let data: ChainData?
    let errors: [SourceError]?

    enum CodingKeys: String, CodingKey {
        case pullTime = "pull_time"
        case command, flight, data, errors
    }
}

/// Envelope C: /api/swim/* feeds. Empty results with total_raw_messages == 0
/// means the feed was quiet, NOT a failure.
nonisolated struct SwimEnvelope: Codable, Sendable {
    let feed: String?
    let timestamp: String?
    let totalRawMessages: Int?
    let filteredResults: Int?
    let results: [JSONValue]?
    let error: String?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case feed, timestamp
        case totalRawMessages = "total_raw_messages"
        case filteredResults = "filtered_results"
        case results, error, detail
    }

    var isQuiet: Bool { (totalRawMessages ?? 0) == 0 && error == nil }
}
