import Foundation

nonisolated enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .http(let code, let message):
            return message.isEmpty ? "Server error (\(code))." : message
        case .server(let message):
            return message
        case .decoding:
            return "Unexpected response from the flight engine."
        }
    }
}

/// Client for the Pro Flight Tracker engine on Railway.
/// Requests carry a bearer token when one is configured; all data-source
/// keys live server-side.
nonisolated enum API {
    static let baseURL = "https://pro-flight-tracker-production.up.railway.app"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 75
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    // MARK: - Core transport

    private static func url(_ path: String, _ query: [String: String?]) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private static func perform(_ request: URLRequest) async throws -> Data {
        // Every call — GET, POST, DELETE — funnels through here, so this is
        // the single place the backend auth header is attached. The backend
        // accepts requests without it, so an unconfigured token is harmless.
        var request = request
        let token = Config.EXPO_PUBLIC_BACKEND_API_TOKEN
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("No response from the flight engine.")
        }
        guard (200...299).contains(http.statusCode) else {
            // Error bodies are JSON with an "error" field on this API.
            if let payload = try? JSONDecoder().decode(JSONValue.self, from: data),
               let message = payload["error"]?.stringValue {
                throw APIError.http(http.statusCode, message)
            }
            throw APIError.http(http.statusCode, "")
        }
        return data
    }

    static func get<T: Decodable & Sendable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        let request = URLRequest(url: try url(path, query))
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[API] decode failure at \(path): \(error)")
            throw APIError.decoding("\(error)")
        }
    }

    static func getJSON(_ path: String, query: [String: String?] = [:]) async throws -> JSONValue {
        try await get(path, query: query)
    }

    // MARK: - Flight (AeroAPI-backed — costs money, call sparingly)

    static func flightStatus(flight: String, date: String?) async throws -> FlightStatusEnvelope {
        try await get("/api/flight/status", query: ["flight": flight, "date": date])
    }

    static func flightChain(flight: String, date: String?) async throws -> ChainEnvelope {
        try await get("/api/flight/chain", query: ["flight": flight, "date": date])
    }

    static func flightTrack(flight: String?, reg: String?) async throws -> TrackEnvelope {
        try await get("/api/flight/track", query: ["flight": flight, "reg": reg])
    }

    /// Horizon-gated analysis + verdict. Costs 2–4 AeroAPI queries per call —
    /// strictly user-initiated, never polled or fired for multiple flights at once.
    static func brief(flight: String, date: String?) async throws -> BriefEnvelope {
        try await get("/api/brief", query: ["flight": flight, "date": date])
    }

    // MARK: - Weather (free)

    static func metar(icaos: [String]) async throws -> MetarEnvelope {
        try await get("/api/weather/metar", query: ["icao": icaos.joined(separator: ",")])
    }

    static func taf(icaos: [String]) async throws -> TafEnvelope {
        try await get("/api/weather/taf", query: ["icao": icaos.joined(separator: ",")])
    }

    static func faaStatus(icaos: [String]) async throws -> FaaStatusEnvelope {
        try await get("/api/weather/faa-status", query: ["icao": icaos.joined(separator: ",")])
    }

    static func sigmets() async throws -> JSONValue {
        try await getJSON("/api/weather/sigmet")
    }

    /// International SIGMETs — everywhere the CONUS `sigmet` feed doesn't
    /// reach. Only worth calling when the route leaves CONUS; for a domestic
    /// pair `sigmet` already covers the airspace and this would duplicate it.
    static func internationalSigmets() async throws -> [InternationalSigmet] {
        let payload = try await getJSON("/api/weather/isigmet")
        // Bare array, or an object wrapping one alongside a count.
        let items: [JSONValue]
        if let array = payload.arrayValue {
            items = array
        } else if let object = payload.objectValue {
            items = object.values.compactMap(\.arrayValue).first ?? []
        } else {
            items = []
        }
        let data = try JSONEncoder().encode(items)
        return (try? JSONDecoder().decode([InternationalSigmet].self, from: data)) ?? []
    }

    static func pireps(icao: String) async throws -> JSONValue {
        try await getJSON("/api/weather/pirep", query: ["icao": icao, "distance": "150"])
    }

    // MARK: - Airport ops (free)

    static func lightning(icao: String) async throws -> LightningEnvelope {
        try await get("/api/ops/lightning", query: ["icao": icao, "duration": "5", "radius": "20"])
    }

    /// FAA TFM Convective Forecast filtered to a route — the product traffic
    /// management uses to call thunderstorm ground stops 2–6h out.
    static func convectiveForecast(originIcao: String, destIcao: String) async throws -> TcfEnvelope {
        try await get("/api/ops/tcf", query: ["route": "\(originIcao),\(destIcao)"])
    }

    static func rvr(airportIcao: String) async throws -> JSONValue {
        // The RVR endpoint wants FAA codes: strip the K prefix for US airports.
        var code = airportIcao
        if code.count == 4, code.hasPrefix("K") { code = String(code.dropFirst()) }
        return try await getJSON("/api/ops/rvr", query: ["airport": code])
    }

    // MARK: - FAA SWIM (free, slow — live broker capture)

    static func notams(airportIcao: String) async throws -> SwimEnvelope {
        try await get("/api/swim/notams", query: ["airport": airportIcao, "duration": "12"])
    }

    static func itws(airportIcao: String) async throws -> SwimEnvelope {
        try await get("/api/swim/itws", query: ["airport": airportIcao, "duration": "8"])
    }

    // MARK: - Tracking service

    @discardableResult
    static func startTracking(flight: String, date: String, intervalMinutes: Int,
                              pushToken: String) async throws -> JSONValue {
        var request = URLRequest(url: try url("/api/track", [:]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: JSONValue] = [
            "flight": .string(flight),
            "date": .string(date),
            "push_token": .string(pushToken),
            "interval_minutes": .number(Double(intervalMinutes)),
        ]
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await perform(request)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func stopTracking(flight: String, date: String) async throws {
        var components = URLComponents(string: baseURL + "/api/track")
        components?.queryItems = [
            URLQueryItem(name: "flight", value: flight),
            URLQueryItem(name: "date", value: date),
        ]
        guard let url = components?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? await perform(request) // 404 (not tracked) is fine to ignore
    }
}
