import Foundation

/// Mirrors the backend brief's horizon gating: same-day live sources (current
/// METAR, FAA programs, lightning, RVR, PIREPs, NOTAMs, and the aircraft's
/// inbound chain) only carry signal inside the same-day window. Beyond it,
/// fetching them wastes paid queries and produces noise that contradicts the
/// brief — so both the fetches and the signal engine gate on this.
nonisolated enum HorizonGate {
    /// Boundary between "same-day sources carry signal" and "too far out".
    /// Matches the brief's own query budget switch (2 queries past 12h, 4 inside).
    static let sameDayWindowHours: Double = 12

    /// Hours until scheduled departure. Negative once the flight has left.
    static func hoursToDeparture(_ flight: AeroFlight?) -> Double? {
        guard let dep = TimeFmt.parseISO(flight?.scheduledOut)
            ?? TimeFmt.parseISO(flight?.estimatedOut) else { return nil }
        return dep.timeIntervalSinceNow / 3600
    }

    /// True when same-day live sources are worth consulting for this flight.
    /// Unknown departure time defaults to true (never blind the imminent case).
    static func sameDaySourcesCarrySignal(hoursToDeparture: Double?) -> Bool {
        guard let hours = hoursToDeparture else { return true }
        return hours <= sameDayWindowHours
    }

    /// True when either end of the route sits outside the contiguous US, i.e.
    /// the domestic SIGMET feed has a coverage gap worth filling with the
    /// international one. A K-prefixed pair is fully covered domestically.
    static func routeLeavesConus(origin: String?, dest: String?) -> Bool {
        let codes = [origin, dest].compactMap { $0 }.filter { !$0.isEmpty }
        guard !codes.isEmpty else { return false }
        return codes.contains { !$0.uppercased().hasPrefix("K") }
    }
}
