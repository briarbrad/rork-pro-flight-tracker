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

    /// Folds the live envelope's server-computed times back into the
    /// last-known leg so the header and the derived-phase guard never lag the
    /// live layer: ACTUAL entries become actual_* milestones, live
    /// predictions refresh the estimated_* slots, and a CANCELLED phase sets
    /// the cancelled flag. (TAXI_IN's landing milestone isn't in
    /// predicted_times — harmless, because the server phase wins whenever a
    /// live layer is present; the derived guard only covers its absence.)
    static func patchedLeg(_ leg: AeroFlight, with envelope: LiveEnvelope) -> AeroFlight {
        var updated = leg
        if envelope.phase?.code == DerivedFlightPhase.cancelled.rawValue {
            updated.cancelled = true
        }
        apply(envelope.predictedTimes?.gateDeparture,
              actual: &updated.actualOut, estimated: &updated.estimatedOut)
        apply(envelope.predictedTimes?.takeoff,
              actual: &updated.actualOff, estimated: &updated.estimatedOff)
        apply(envelope.predictedTimes?.gateArrival,
              actual: &updated.actualIn, estimated: &updated.estimatedIn)
        return updated
    }

    private static func apply(_ entry: BriefPredictedTime?,
                              actual: inout String?, estimated: inout String?) {
        guard let entry, let time = entry.time, !time.isEmpty else { return }
        if entry.isActual {
            actual = time
        } else if !entry.isScheduledOnly, !entry.isUnknown {
            estimated = time
        }
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
