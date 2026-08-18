import Foundation

/// How a predicted schedule delta should be treated, judged against the
/// brief's own stated uncertainty band for the current horizon.
nonisolated enum DeltaSignificance {
    /// No late delta — the reassuring "on time" state.
    case onTime
    /// Small delta inside the uncertainty band with NO identified cause —
    /// noise, not signal. Never wears delay coloring.
    case noise
    /// Small delta inside the band but WITH a real identified mechanism
    /// behind it (e.g. an EDCT) — small, yet still a genuine delay signal.
    case causedMinor
    /// Delta exceeds the stated band — an actionable delay regardless of cause.
    case significant
}

/// Compares predicted deltas against the brief's uncertainty band and names
/// the active cause (if the brief identified one). One instance serves both
/// the delta-chip styling in the trip timeline and the one-line inline
/// explanation beneath it, so the two can never disagree.
nonisolated struct DeltaExplainer {
    /// The "±N min at this horizon" band the brief itself stated. Nil when
    /// the backend sent no band — deltas then keep the conservative
    /// (delay-styled) treatment rather than being silently dismissed.
    let uncertaintyMinutes: Int?
    /// Short name of the identified mechanism driving the delta, or nil when
    /// the brief found no active cause. EDCT beats effects: an FAA-assigned
    /// slot is the hardest possible explanation.
    let activeCause: String?

    init(times: BriefPredictedTimes?, effects: [BriefEffect]?) {
        uncertaintyMinutes = times?.uncertaintyMinutes
        if times?.edct?.edct != nil {
            activeCause = "an FAA-assigned takeoff slot (EDCT)"
        } else if let cause = effects?.first(where: {
            $0.severityCode == "ACTION" || $0.severityCode == "WATCH"
        })?.cause {
            activeCause = cause
        } else {
            activeCause = nil
        }
    }

    var hasActiveCause: Bool { activeCause != nil }

    /// Classifies one predicted delta. Applies to PREDICTIONS — actual
    /// (already-happened) times are facts and stay factual at the call site.
    func significance(of delayMin: Int?) -> DeltaSignificance {
        guard let delayMin, delayMin > 0 else { return .onTime }
        guard let band = uncertaintyMinutes, band > 0 else {
            // No stated band: nothing to judge noise against — treat as real.
            return .significant
        }
        if delayMin > band { return .significant }
        return hasActiveCause ? .causedMinor : .noise
    }

    /// The largest late prediction across the three columns — what the inline
    /// explanation talks about. Late ACTUALS count too (a fact worth
    /// explaining); early/on-time entries don't.
    func maxLateDelta(in times: BriefPredictedTimes) -> Int? {
        let deltas = [times.gateDeparture, times.takeoff, times.gateArrival]
            .compactMap { entry -> Int? in
                guard let entry, !entry.isUnknown,
                      let delay = entry.delayVsScheduleMin, delay > 0 else { return nil }
                return delay
            }
        return deltas.max()
    }

    /// One plain-English line for beneath the trip timeline whenever a
    /// milestone shows a late delta. Nil when everything is on time or early.
    func explanationLine(for times: BriefPredictedTimes) -> String? {
        guard let delta = maxLateDelta(in: times) else { return nil }
        let bandText = uncertaintyMinutes.map { "±\($0) min" }

        if let cause = activeCause {
            if let bandText, delta <= (uncertaintyMinutes ?? 0) {
                return "+\(delta) min is inside the \(bandText) band for this horizon, but it has a real cause: \(cause)."
            }
            return "The +\(delta) min slip is driven by \(cause)."
        }
        if let band = uncertaintyMinutes, band > 0 {
            if delta <= band {
                return "No active cause identified — +\(delta) min is within the ±\(band) min normal variance at this horizon."
            }
            return "+\(delta) min exceeds the ±\(band) min uncertainty at this horizon, but no single cause was identified in the sources checked."
        }
        return "No active cause identified for the +\(delta) min slip in the sources checked."
    }

    /// Short note for the effects block when the brief found no direct cause
    /// yet a small delta is visible on the same screen — keeps "no cause
    /// found" from reading as a contradiction of the colored chip.
    func unexplainedDeltaNote(for times: BriefPredictedTimes?) -> String? {
        guard !hasActiveCause, let times, let delta = maxLateDelta(in: times) else { return nil }
        if let band = uncertaintyMinutes, band > 0, delta <= band {
            return "The +\(delta) min predicted slip above has no identified cause — within normal schedule variance, not a known problem."
        }
        return "The +\(delta) min predicted slip above has no identified cause in the sources checked."
    }
}
