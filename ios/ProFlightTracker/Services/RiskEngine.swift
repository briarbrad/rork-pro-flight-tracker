import Foundation

/// Client-side signal engine. Watches the sources that still carry signal at
/// the flight's current horizon and surfaces changes between checks.
///
/// This is deliberately NOT a flight-level verdict — that comes exclusively
/// from /api/brief. The engine mirrors the brief's horizon gating so the two
/// can never contradict each other on the same screen:
/// - Same-day sources (current METAR, FAA programs, lightning, the aircraft
///   chain) are only evaluated inside the same-day window (~12h).
/// - Sources the last brief explicitly excluded are filtered out entirely, so
///   they can't drive signals, alerts, or the risk color.
nonisolated enum RiskEngine {

    static func evaluate(flight: AeroFlight?,
                         chain: ChainData?,
                         faa: [String: FaaAirportStatus]?,
                         metar: [String: MetarObservation]?,
                         taf: [String: TafReport]?,
                         lightning: FlightSnapshot.LightningWrapper?,
                         hoursToDeparture: Double? = nil,
                         excludedSources: Set<String> = []) -> RiskAssessment {
        var signals: [RiskSignal] = []
        let sameDayWindow = HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: hoursToDeparture)

        // The flight's own status feed is always in play, whatever the horizon.
        appendFlightSignals(flight, into: &signals)

        // Same-day live sources only mean something inside the window —
        // beyond it a storm or GDP happening right now will clear long before
        // departure and must not color the flight.
        if sameDayWindow {
            appendFaaSignals(faa, into: &signals)
            appendChainSignals(chain, into: &signals)
            appendMetarSignals(metar, into: &signals)
            appendLightningSignals(lightning, into: &signals)
        }

        // TAF reaches 24–30h out, so it stays live at long horizons — but only
        // the periods around the actual departure window.
        appendTafSignals(taf, departure: TimeFmt.parseISO(flight?.scheduledOut), into: &signals)

        // Anything the brief flagged as signal-less at this horizon must not
        // appear as a driver, fire an alert, or affect the risk color.
        if !excludedSources.isEmpty {
            signals = signals.filter { !matchesExcludedSource($0.key, excludedSources) }
        }

        let level = signals.map(\.level).reduce(RiskLevel.low, RiskLevel.worse)
        return RiskAssessment(level: level, signals: signals, evaluatedAt: Date())
    }

    /// Maps a signal key onto the brief's source vocabulary and checks whether
    /// that source was excluded. Matching is by token so minor naming drift on
    /// the backend ("metar_current" vs "current_metar") still matches.
    static func matchesExcludedSource(_ key: String, _ excluded: Set<String>) -> Bool {
        let sources = excluded.map { $0.lowercased() }
        func hit(_ tokens: [String]) -> Bool {
            sources.contains { source in tokens.contains { source.contains($0) } }
        }
        if key.hasPrefix("chain.") { return hit(["chain", "inbound"]) }
        if key.hasPrefix("faa.") { return hit(["faa", "nas", "airport_status", "ground_stop", "ground_delay"]) }
        if key.hasPrefix("ops.") { return hit(["lightning"]) }
        if key.hasPrefix("wx.") {
            if key.contains(".taf") { return hit(["taf", "forecast"]) }
            return hit(["metar", "current", "observation"])
        }
        return false // The flight's own status feed is never excluded.
    }

    // MARK: - The flight itself (mirrors backend thresholds)

    private static func appendFlightSignals(_ flight: AeroFlight?, into signals: inout [RiskSignal]) {
        guard let flight else { return }

        if flight.cancelled == true {
            signals.append(RiskSignal(
                key: "flight.cancelled", title: "Flight cancelled",
                detail: "The airline has cancelled this flight.",
                level: .high, icon: "circle-x"))
            return
        }
        if flight.diverted == true {
            signals.append(RiskSignal(
                key: "flight.diverted", title: "Flight diverted",
                detail: "This flight has been diverted from its planned destination.",
                level: .high, icon: "split"))
        }

        let status = (flight.status ?? "").lowercased()
        if status.contains("cancel") {
            signals.append(RiskSignal(
                key: "flight.status-cancel", title: "Cancellation reported",
                detail: "Status feed reports: \(flight.status ?? "")",
                level: .high, icon: "circle-x"))
        } else if status.contains("delay") {
            signals.append(RiskSignal(
                key: "flight.status-delay", title: "Delay in status feed",
                detail: "Status feed reports: \(flight.status ?? "")",
                level: .moderate, icon: "clock-alert"))
        }

        if let slip = flight.departureSlipMinutes {
            switch SlipSeverity.of(minutes: slip) {
            case .alert:
                signals.append(RiskSignal(
                    key: "flight.dep-slip-major", title: "Departure slipping badly",
                    detail: "Departure is running \(Int(slip)) min behind schedule.",
                    level: .high, icon: "clock-alert"))
            case .watch:
                signals.append(RiskSignal(
                    key: "flight.dep-slip", title: "Departure slipping",
                    detail: "Departure is running \(Int(slip)) min behind schedule.",
                    level: .moderate, icon: "clock"))
            case .none:
                break
            }
        }

        if let slip = flight.arrivalSlipMinutes, slip >= 30, flight.actualIn == nil {
            signals.append(RiskSignal(
                key: "flight.arr-slip", title: "Arrival trending late",
                detail: "Arrival is projected \(Int(slip)) min behind schedule.",
                level: .moderate, icon: "plane-landing"))
        }
    }

    // MARK: - FAA delay programs (same-day window only)

    private static func appendFaaSignals(_ faa: [String: FaaAirportStatus]?, into signals: inout [RiskSignal]) {
        guard let faa else { return }
        for (icao, record) in faa.sorted(by: { $0.key < $1.key }) {
            if !(record.groundStops ?? []).isEmpty {
                signals.append(RiskSignal(
                    key: "faa.\(icao).ground-stop", title: "Ground stop at \(icao)",
                    detail: "The FAA has issued a ground stop affecting \(icao).",
                    level: .high, icon: "octagon-alert"))
            }
            if !(record.groundDelayPrograms ?? []).isEmpty {
                let delayNote = record.gdpDelaySummary.map { " Current \($0.replacingOccurrences(of: "avg", with: "average delay"))." } ?? ""
                signals.append(RiskSignal(
                    key: "faa.\(icao).gdp", title: "Ground delay program at \(icao)",
                    detail: "A ground delay program is active — expect metered departures and EDCT holds.\(delayNote)",
                    level: .moderate, icon: "timer"))
            }
            if !(record.arrivalDepartureDelays ?? []).isEmpty {
                var detail = "Active arrival/departure delays reported by FAA NAS status."
                if let range = record.delayRangeText {
                    detail = "FAA NAS status reports delays of \(range) at \(icao)."
                    if let trend = record.delayTrend {
                        detail += trend == "increasing" ? " Delays are trending up." : " Delays are easing."
                    }
                }
                signals.append(RiskSignal(
                    key: "faa.\(icao).delays", title: "FAA delays at \(icao)",
                    detail: detail,
                    level: .moderate, icon: "hourglass"))
            }
            if !(record.closures ?? []).isEmpty {
                signals.append(RiskSignal(
                    key: "faa.\(icao).closure", title: "Closure at \(icao)",
                    detail: "A runway or airport closure is in effect at \(icao).",
                    level: .moderate, icon: "construction"))
            }
        }
    }

    // MARK: - Aircraft chain (same-day window only)

    private static func appendChainSignals(_ chain: ChainData?, into signals: inout [RiskSignal]) {
        guard let chain else { return }

        if let turn = chain.turnAnalysis, let minutes = turn.turnTimeAvailableMin {
            if minutes < 0 {
                signals.append(RiskSignal(
                    key: "chain.turn-negative", title: "Inbound lands after departure",
                    detail: turn.note ?? "Your aircraft arrives after this flight is scheduled to leave — a delay is certain.",
                    level: .high, icon: "link-2-off"))
            } else if turn.sufficient == false {
                signals.append(RiskSignal(
                    key: "chain.turn-tight", title: "Turn time too tight",
                    detail: turn.note ?? "The aircraft's ground turn is below the minimum for this type.",
                    level: .moderate, icon: "timer"))
            }
        }

        if let inbound = chain.inboundFlight {
            if inbound.cancelled == true {
                signals.append(RiskSignal(
                    key: "chain.inbound-cancelled", title: "Inbound aircraft cancelled",
                    detail: "The previous leg (\(inbound.ident ?? "inbound")) was cancelled — your aircraft may be swapped or your flight delayed.",
                    level: .high, icon: "plane-takeoff"))
            } else if let slip = TimeFmt.slipMinutes(scheduled: inbound.scheduledIn,
                                                     actual: inbound.actualIn,
                                                     estimated: inbound.estimatedIn),
                      SlipSeverity.of(minutes: slip).isSlipped, inbound.actualIn == nil,
                      !turnAbsorbsLateness(chain.turnAnalysis) {
                signals.append(RiskSignal(
                    key: "chain.inbound-late", title: "Inbound aircraft running late",
                    detail: "\(inbound.ident ?? "The previous leg") is trending \(Int(slip)) min late into \(inbound.destDisplay).",
                    level: .moderate, icon: "plane-landing"))
            }
        }
    }

    /// A late inbound is only a risk if it erodes the turn below standard.
    /// The backend computes turn availability from the inbound's CURRENT eta,
    /// so `sufficient == true` means the lateness is already absorbed — a
    /// 40-min-late inbound with 526 min on the ground is not a warning.
    private static func turnAbsorbsLateness(_ turn: TurnAnalysis?) -> Bool {
        guard let turn else { return false }
        if let sufficient = turn.sufficient { return sufficient }
        if let available = turn.turnTimeAvailableMin,
           let standard = turn.turnTimeRequiredMinStandard {
            return available >= standard
        }
        return false
    }

    // MARK: - Current weather observations (same-day window only)

    private static func appendMetarSignals(_ metar: [String: MetarObservation]?,
                                           into signals: inout [RiskSignal]) {
        guard let metar else { return }
        for (icao, ob) in metar.sorted(by: { $0.key < $1.key }) {
            let category = (ob.flightCategory ?? "").uppercased()
            if category == "LIFR" {
                signals.append(RiskSignal(
                    key: "wx.\(icao).lifr", title: "Very low conditions at \(icao)",
                    detail: "LIFR: \(ob.decoded)",
                    level: .moderate, icon: "cloud-fog"))
            } else if category == "IFR" {
                signals.append(RiskSignal(
                    key: "wx.\(icao).ifr", title: "IFR conditions at \(icao)",
                    detail: ob.decoded,
                    level: .moderate, icon: "cloud-fog"))
            }
            if let gust = ob.wind?.gustKts, gust >= 30 {
                signals.append(RiskSignal(
                    key: "wx.\(icao).gusts", title: "Strong gusts at \(icao)",
                    detail: "Wind gusting \(Int(gust)) kt — expect flow restrictions.",
                    level: .moderate, icon: "wind"))
            }
            let wx = (ob.weatherPhenomena ?? "").uppercased()
            if wx.contains("TS") {
                signals.append(RiskSignal(
                    key: "wx.\(icao).ts", title: "Thunderstorms at \(icao)",
                    detail: "Storms are being reported on the field right now.",
                    level: .moderate, icon: "cloud-lightning"))
            } else if wx.contains("FZ") {
                signals.append(RiskSignal(
                    key: "wx.\(icao).fz", title: "Freezing precipitation at \(icao)",
                    detail: "Freezing conditions reported — deicing delays likely.",
                    level: .moderate, icon: "snowflake"))
            }
        }
    }

    // MARK: - Terminal forecast (scoped to the departure window)

    private static func appendTafSignals(_ taf: [String: TafReport]?,
                                         departure: Date?,
                                         into signals: inout [RiskSignal]) {
        guard let taf else { return }

        // Only forecast periods overlapping the departure window matter —
        // a TS group 14h before a next-day departure is noise, not signal.
        let windowStart: Date
        let windowEnd: Date
        if let departure, departure > Date() {
            windowStart = departure.addingTimeInterval(-3 * 3600)
            windowEnd = departure.addingTimeInterval(2 * 3600)
        } else {
            windowStart = Date()
            windowEnd = Date().addingTimeInterval(12 * 3600)
        }

        for (icao, report) in taf.sorted(by: { $0.key < $1.key }) {
            let stormPeriod = (report.forecastPeriods ?? []).first { period in
                guard let from = TimeFmt.parseISO(period.timeFrom) else { return false }
                let to = TimeFmt.parseISO(period.timeTo) ?? from.addingTimeInterval(6 * 3600)
                guard from <= windowEnd, to >= windowStart else { return false }
                return (period.weather ?? "").uppercased().contains("TS")
            }
            if stormPeriod != nil {
                signals.append(RiskSignal(
                    key: "wx.\(icao).taf-ts", title: "Storms forecast at \(icao)",
                    detail: "The terminal forecast calls for thunderstorms around your departure window.",
                    level: .moderate, icon: "cloud-lightning"))
            }
        }
    }

    // MARK: - Lightning (same-day window only)

    private static func appendLightningSignals(_ lightning: FlightSnapshot.LightningWrapper?,
                                               into signals: inout [RiskSignal]) {
        guard let lightning else { return }
        let icao = lightning.airport ?? "airport"
        if let close = lightning.strikesWithin5nm, close > 0 {
            signals.append(RiskSignal(
                key: "ops.\(icao).lightning-close", title: "Lightning within 5 nm of \(icao)",
                detail: "\(close) strike\(close == 1 ? "" : "s") detected close-in — ramp closures stop boarding and fueling.",
                level: .moderate, icon: "zap"))
        } else if let risk = lightning.rampClosureRisk?.uppercased(),
                  risk.contains("HIGH") || risk.contains("ELEVATED") {
            signals.append(RiskSignal(
                key: "ops.\(icao).lightning-risk", title: "Lightning near \(icao)",
                detail: "Ramp closure risk is \(lightning.rampClosureRisk ?? "elevated") with \(lightning.totalStrikes ?? 0) strikes in the area.",
                level: .moderate, icon: "zap"))
        }
    }
}
