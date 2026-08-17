import Foundation

/// The two zones a flight's times live in: departure facts read in the origin's
/// local time, arrival facts in the destination's. Resolved once per screen and
/// passed down, so no view has to guess which end a timestamp belongs to.
nonisolated struct FlightZones: Hashable, Sendable {
    let origin: TimeZone?
    let destination: TimeZone?

    static let unknown = FlightZones(origin: nil, destination: nil)

    /// Backend zones win when present (they're what its `local_display` strings
    /// were built from), then the bundled airport table.
    static func resolve(flight: AeroFlight?, brief: BriefTimezones? = nil) -> FlightZones {
        FlightZones(
            origin: AirportTimeZones.named(brief?.origin)
                ?? AirportTimeZones.zone(forAnyOf: flight?.originIcao, flight?.originIata),
            destination: AirportTimeZones.named(brief?.destination)
                ?? AirportTimeZones.zone(forAnyOf: flight?.destIcao, flight?.destIata))
    }

    /// Zone for an airport code that belongs to this flight, falling back to the
    /// bundled table for anything else (an inbound leg's other airport, say).
    func zone(forAirport code: String?, flight: AeroFlight?) -> TimeZone? {
        guard let code, !code.isEmpty else { return nil }
        let target = code.uppercased()
        if [flight?.originIcao, flight?.originIata].compactMap({ $0?.uppercased() }).contains(target) {
            return origin
        }
        if [flight?.destIcao, flight?.destIata].compactMap({ $0?.uppercased() }).contains(target) {
            return destination
        }
        return AirportTimeZones.zone(for: code)
    }

    var isSingleZone: Bool {
        guard let origin, let destination else { return false }
        return origin.identifier == destination.identifier
    }
}
