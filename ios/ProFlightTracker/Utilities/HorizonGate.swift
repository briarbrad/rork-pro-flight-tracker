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

    /// Equipment chain is a paid 2–3 query lookup that only describes the
    /// inbound aircraft's turn. The brief skips it past 12h (assignment is
    /// unreliable) and from `TAXI_OUT` onward (the turn already happened).
    /// Mirror both gates so a refresh never buys a chain the brief would ignore.
    static func equipmentChainCarriesSignal(hoursToDeparture: Double?,
                                            phaseCode: String?) -> Bool {
        guard sameDaySourcesCarrySignal(hoursToDeparture: hoursToDeparture) else {
            return false
        }
        return isPreGate(phaseCode)
    }

    /// Origin-surface now-casts (lightning, ramp closures) only affect this
    /// departure while the aircraft is still on the origin ramp. Unknown
    /// phase defaults to true so we never blind the imminent case.
    static func originSurfaceOpsCarrySignal(hoursToDeparture: Double?,
                                            phaseCode: String?) -> Bool {
        guard sameDaySourcesCarrySignal(hoursToDeparture: hoursToDeparture) else {
            return false
        }
        let code = (phaseCode ?? "").uppercased()
        if code.isEmpty { return true }
        return code == DerivedFlightPhase.preGate.rawValue
            || code == DerivedFlightPhase.taxiOut.rawValue
    }

    /// True when the aircraft has not yet left the gate, or we don't know.
    static func isPreGate(_ phaseCode: String?) -> Bool {
        let code = (phaseCode ?? "").uppercased()
        return code.isEmpty || code == DerivedFlightPhase.preGate.rawValue
    }

    /// Physically between gate and gate — the window where a live position
    /// is worth a (usually free) track pull.
    static func isEnRoute(_ phaseCode: String?) -> Bool {
        let code = (phaseCode ?? "").uppercased()
        return code == DerivedFlightPhase.taxiOut.rawValue
            || code == DerivedFlightPhase.airborne.rawValue
            || code == DerivedFlightPhase.taxiIn.rawValue
    }
}
