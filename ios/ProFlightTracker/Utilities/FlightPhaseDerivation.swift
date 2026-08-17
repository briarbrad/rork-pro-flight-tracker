import Foundation

/// Client-derived flight phase — the single source of truth for every phase
/// display. The AeroAPI milestones (actual_out/off/on/in) are monotonic facts
/// from the live status pull, so deriving from them can never lag the way a
/// stored brief can: the brief is written once by runBrief(), while the main
/// refresh keeps updating the flight underneath it.
nonisolated enum DerivedFlightPhase: String, Sendable {
    case preGate = "PRE_GATE"
    case taxiOut = "TAXI_OUT"
    case airborne = "AIRBORNE"
    case taxiIn = "TAXI_IN"
    case arrived = "ARRIVED"
    case cancelled = "CANCELLED"

    var label: String {
        switch self {
        case .preGate: return "Not yet departed"
        case .taxiOut: return "Taxiing out"
        case .airborne: return "In the air"
        case .taxiIn: return "Landed, taxiing in"
        case .arrived: return "Arrived"
        case .cancelled: return "Cancelled"
        }
    }
}

nonisolated enum FlightPhaseDerivation {
    /// Pure milestone → phase mapping in strict priority order. Later
    /// milestones win: a set actual_in implies the earlier ones happened.
    static func phase(for flight: AeroFlight) -> DerivedFlightPhase {
        if flight.cancelled == true { return .cancelled }
        if flight.actualIn != nil { return .arrived }
        if flight.actualOn != nil { return .taxiIn }
        if flight.actualOff != nil { return .airborne }
        if flight.actualOut != nil { return .taxiOut }
        return .preGate
    }

    /// Minimal replacement phase for when the brief's phase no longer matches
    /// reality: code + label + which event comes next. Deliberately carries no
    /// taxi/position enrichment and no minutes — the client doesn't know them,
    /// and pretending otherwise is the bug this fixes.
    static func minimalBriefPhase(for flight: AeroFlight) -> BriefPhase {
        let derived = phase(for: flight)
        return BriefPhase(
            phase: derived.rawValue,
            phaseLabel: derived.label,
            phaseDetail: nil,
            elapsedInPhaseMin: nil,
            nextEvent: nextEventKey(for: derived),
            nextEventLabel: nextEventLabel(for: derived),
            nextEventLocalDisplay: nil,
            nextEventBasis: nil,
            nextEventStatus: nil,
            nextEventOverdue: nil,
            minutesToNextEvent: nil)
    }

    /// Promotes reported actual_* milestones over their predicted slots: a
    /// future "Arrival" prediction must never render once actual_in is set.
    /// Server-provided ACTUAL entries are kept verbatim (they carry the
    /// backend's local_display); only non-actual predictions are replaced.
    static func reconciledPredictions(_ times: BriefPredictedTimes?,
                                      with flight: AeroFlight) -> BriefPredictedTimes? {
        guard let times else { return nil }
        return BriefPredictedTimes(
            gateDeparture: reconciled(times.gateDeparture, actual: flight.actualOut),
            takeoff: reconciled(times.takeoff, actual: flight.actualOff),
            gateArrival: reconciled(times.gateArrival, actual: flight.actualIn),
            uncertaintyMinutes: times.uncertaintyMinutes,
            uncertaintyNote: times.uncertaintyNote,
            edct: times.edct)
    }

    private static func reconciled(_ entry: BriefPredictedTime?,
                                   actual: String?) -> BriefPredictedTime? {
        guard let actual, !actual.isEmpty else { return entry }
        if entry?.isActual == true { return entry }
        return BriefPredictedTime(
            time: actual,
            timeLocal: nil,
            localDisplay: nil,
            utcDisplay: nil,
            timezone: nil,
            status: "ACTUAL",
            basis: "Actual time reported by the live flight status — replaces the earlier prediction.",
            delayVsScheduleMin: nil)
    }

    /// Which predicted_times key comes next for a derived phase — mirrors the
    /// backend's own next_event mapping so the existing lookup keeps working.
    private static func nextEventKey(for phase: DerivedFlightPhase) -> String? {
        switch phase {
        case .preGate: return "gate_departure"
        case .taxiOut: return "takeoff"
        case .airborne, .taxiIn: return "gate_arrival"
        case .arrived, .cancelled: return nil
        }
    }

    private static func nextEventLabel(for phase: DerivedFlightPhase) -> String? {
        switch phase {
        case .preGate: return "Gate departure"
        case .taxiOut: return "Takeoff"
        case .airborne, .taxiIn: return "Gate arrival"
        case .arrived, .cancelled: return nil
        }
    }
}
