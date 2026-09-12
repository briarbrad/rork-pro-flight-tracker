//
//  ProFlightTrackerTests.swift
//  ProFlightTrackerTests
//
//  Created by Rork on August 16, 2026.
//

import Testing
@testable import ProFlightTracker

struct ProFlightTrackerTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

/// The outlook line is promoted VERBATIM from the narrative's forward-looking
/// section — and omitted entirely when the narrative names no forward risk.
struct NarrativeOutlookTests {

    @Test func extractsFirstItemUnderChangeThePictureHeading() {
        let narrative = """
        ## Current Picture
        The flight is running about 4 minutes behind.

        ## What Would Change the Picture
        - Inbound delay >10 minutes → turn time drops to ~46 min → departure hold becomes likely
        - A ground stop at the destination
        """
        let line = NarrativeOutlook.outlookLine(from: narrative)
        #expect(line == "Inbound delay >10 minutes → turn time drops to ~46 min → departure hold becomes likely")
    }

    @Test func supportsBoldHeadingsAndNumberedItems() {
        let narrative = """
        **Assessment**
        Nothing actionable yet.

        **What Would Change the Picture:**
        1. TEMPO thunderstorms verify at the origin between 4-6 PM
        """
        let line = NarrativeOutlook.outlookLine(from: narrative)
        #expect(line == "TEMPO thunderstorms verify at the origin between 4-6 PM")
    }

    @Test func noForwardSectionMeansNoLine() {
        let narrative = "## Summary\nAll clear. Expect an on-time departure."
        #expect(NarrativeOutlook.outlookLine(from: narrative) == nil)
    }

    @Test func nothingIdentifiedMeansNoLineNotAPlaceholder() {
        let narrative = """
        ## What Would Change the Picture
        None identified at this horizon.
        """
        #expect(NarrativeOutlook.outlookLine(from: narrative) == nil)
    }

    @Test func emptyNarrativeMeansNoLine() {
        #expect(NarrativeOutlook.outlookLine(from: nil) == nil)
        #expect(NarrativeOutlook.outlookLine(from: "") == nil)
    }
}

/// Push-token gating: preview placeholders must never look deliverable.
struct PushTokenTests {

    @Test func previewPlaceholderIsNotDeliverable() {
        #expect(!PushToken.isDeliverable("rork-ios-preview-\(UUID().uuidString.lowercased())"))
        #expect(!PushToken.isDeliverable(""))
        #expect(!PushToken.isDeliverable("   "))
    }

    @Test func expoTokenIsDeliverable() {
        #expect(PushToken.isDeliverable("ExponentPushToken[abcdefghijklmnopqrstuv]"))
    }
}

/// Horizon gates must match the brief's query budget: no paid chain after
/// pushback or past 12h; origin lightning only while still on the ramp.
struct HorizonGateTests {

    @Test func sameDayWindow() {
        #expect(HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: nil))
        #expect(HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: 6))
        #expect(HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: 12))
        #expect(!HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: 12.1))
        #expect(HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: -2))
    }

    @Test func equipmentChainSkipsDistantAndPostPushback() {
        #expect(HorizonGate.equipmentChainCarriesSignal(hoursToDeparture: 8, phaseCode: "PRE_GATE"))
        #expect(!HorizonGate.equipmentChainCarriesSignal(hoursToDeparture: 15, phaseCode: "PRE_GATE"))
        #expect(!HorizonGate.equipmentChainCarriesSignal(hoursToDeparture: 2, phaseCode: "TAXI_OUT"))
        #expect(!HorizonGate.equipmentChainCarriesSignal(hoursToDeparture: 1, phaseCode: "AIRBORNE"))
        #expect(HorizonGate.equipmentChainCarriesSignal(hoursToDeparture: 4, phaseCode: nil))
    }

    @Test func originLightningFollowsRamp() {
        #expect(HorizonGate.originSurfaceOpsCarrySignal(hoursToDeparture: 3, phaseCode: "PRE_GATE"))
        #expect(HorizonGate.originSurfaceOpsCarrySignal(hoursToDeparture: 1, phaseCode: "TAXI_OUT"))
        #expect(!HorizonGate.originSurfaceOpsCarrySignal(hoursToDeparture: 1, phaseCode: "AIRBORNE"))
        #expect(!HorizonGate.originSurfaceOpsCarrySignal(hoursToDeparture: 20, phaseCode: "PRE_GATE"))
    }

    @Test func routeLeavesConus() {
        #expect(!HorizonGate.routeLeavesConus(origin: "KJFK", dest: "KLAX"))
        #expect(HorizonGate.routeLeavesConus(origin: "KJFK", dest: "EGLL"))
        #expect(HorizonGate.routeLeavesConus(origin: "PHNL", dest: "KLAX"))
        #expect(!HorizonGate.routeLeavesConus(origin: nil, dest: nil))
    }

    @Test func phaseHelpers() {
        #expect(HorizonGate.isPreGate(nil))
        #expect(HorizonGate.isPreGate("PRE_GATE"))
        #expect(!HorizonGate.isPreGate("TAXI_OUT"))
        #expect(HorizonGate.isEnRoute("AIRBORNE"))
        #expect(!HorizonGate.isEnRoute("ARRIVED"))
    }
}

/// Finished flights must stop automatic paid refreshes even without a live layer.
struct FlightSnapshotFinalityTests {

    @Test func arrivedMilestoneIsFinalWithoutLiveLayer() throws {
        var snapshot = FlightSnapshot()
        snapshot.flight = try Self.decodeFlight(["ident": "DL244", "actual_in": "2026-09-12T18:00:00Z"])
        #expect(snapshot.isFinal)
        #expect(!snapshot.autoRefreshDue)
    }

    @Test func cancelledIsFinal() throws {
        var snapshot = FlightSnapshot()
        snapshot.flight = try Self.decodeFlight(["ident": "DL244", "cancelled": true])
        #expect(snapshot.isFinal)
    }

    @Test func scheduledFlightIsNotFinal() throws {
        var snapshot = FlightSnapshot()
        snapshot.flight = try Self.decodeFlight([
            "ident": "DL244",
            "scheduled_out": "2026-09-13T18:00:00Z",
        ])
        #expect(!snapshot.isFinal)
    }

    private static func decodeFlight(_ object: [String: Any]) throws -> AeroFlight {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(AeroFlight.self, from: data)
    }
}

struct ChatErrorTests {

    @Test func fiveOhOneIsNotConfigured() {
        #expect(ChatError.notConfigured.errorDescription == "AI chat is currently unavailable.")
    }
}

/// Trend rendering guards: one check is a data point, not a trend.
struct DelayTrendModelTests {

    private func snapshot(_ delta: Double) -> BriefDelaySnapshot {
        BriefDelaySnapshot(checkedAt: "2026-08-18T20:00:00+00:00",
                           deltaMinutes: delta, risk: "LOW")
    }

    @Test func wideningSeriesHasTrend() {
        let trend = BriefDelayTrend(
            snapshots: [snapshot(2), snapshot(8), snapshot(15)],
            direction: "widening", checks: 3)
        #expect(trend.hasTrend)
        #expect(trend.directionCode == "widening")
    }

    @Test func singleCheckShowsNothing() {
        // Server sends direction nil for a single check; even if it sent a
        // direction, one snapshot must never render as a trend.
        let single = BriefDelayTrend(snapshots: [snapshot(4)],
                                     direction: nil, checks: 1)
        #expect(!single.hasTrend)
        let mislabeled = BriefDelayTrend(snapshots: [snapshot(4)],
                                         direction: "steady", checks: 1)
        #expect(!mislabeled.hasTrend)
    }

    @Test func sparklineNormalizesOldestFirst() {
        let points = DelaySparkline.normalized([2, 8, 15])
        #expect(points.count == 3)
        #expect(points.first == 0)
        #expect(points.last == 1)
        #expect(points[1] > 0 && points[1] < 1)
    }

    @Test func sparklineEmptyWhenNoValues() {
        #expect(DelaySparkline.normalized([]).isEmpty)
    }
}

/// G-AIRMET / ATFM / flow-brief / Open-Meteo decoding — documented shapes,
/// plus the hide-when-empty / hide-when-missing gates.
struct OpsModelTests {

    @Test func gairmetQuietWhenNoRelevantAreas() throws {
        let json = """
        {"route":"KJFK-KLAX","relevant_count":0,"relevant":[],"risk_level":"NONE",
         "summary":"No G-AIRMET advisories along route"}
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(GairmetEnvelope.self, from: json)
        #expect(envelope.isQuiet)
        #expect(envelope.areas.isEmpty)
        #expect(envelope.level == "NONE")
    }

    @Test func gairmetCorridorDecodesSeverityAndBand() throws {
        let json = """
        {"route":"KJFK-KORD","relevant_count":1,"risk_level":"MODERATE","relevant":[{
            "hazard":"TURB-HI","severity":"MOD","base":"180","top":"410",
            "base_ft":18000,"top_ft":41000,"near_origin":true,"near_dest":false,
            "along_route":false
        }]}
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(GairmetEnvelope.self, from: json)
        #expect(!envelope.isQuiet)
        #expect(envelope.nearOriginCount == 1)
        #expect(envelope.areas[0].hazardLabel == "High-altitude turbulence")
        #expect(envelope.areas[0].severityLabel == "Moderate")
        #expect(envelope.areas[0].altitudeBand == "FL180–FL410")
        #expect(envelope.areas[0].whereText == "near departure")
    }

    @Test func atfmShowsOnlyProbableOrPossible() throws {
        let probable = try decodeAtfm(["applicable": true, "verdict": "PROBABLE",
                                       "destination": "EGLL", "delay_min": 25])
        #expect(probable.shouldDisplay)
        #expect(probable.delayMinutes == 25)

        let possible = try decodeAtfm(["applicable": true, "verdict": "POSSIBLE",
                                       "destination": "LFPG"])
        #expect(possible.shouldDisplay)

        let unlikely = try decodeAtfm(["applicable": true, "verdict": "UNLIKELY",
                                       "destination": "EGLL"])
        #expect(!unlikely.shouldDisplay)

        let domestic = try decodeAtfm(["applicable": false,
                                       "reason": "Destination KLAX not in Eurocontrol airspace"])
        #expect(!domestic.shouldDisplay)
    }

    @Test func destInEurocontrolMatchesBackendPrefixes() {
        #expect(HorizonGate.destInEurocontrol("EGLL"))
        #expect(HorizonGate.destInEurocontrol("LFPG"))
        #expect(HorizonGate.destInEurocontrol("LIRF"))
        #expect(HorizonGate.destInEurocontrol("EDDF"))
        #expect(!HorizonGate.destInEurocontrol("KJFK"))
        #expect(!HorizonGate.destInEurocontrol("KLAX"))
        #expect(!HorizonGate.destInEurocontrol("RJTT"))
        #expect(!HorizonGate.destInEurocontrol(nil))
    }

    @Test func flowBriefParsesComposedEffectsAndAdvisories() {
        let json: JSONValue = .object([
            "effects": .array([
                .object([
                    "cause": .string("GDP at KJFK, avg delay 2h"),
                    "effect": .string("Meters arrivals into the origin — INFO for this departure."),
                    "severity": .string("INFO"),
                    "source": .string("tfms_flow"),
                ]),
            ]),
            "advisories": .array([
                .object([
                    "type": .string("tfms_advisory"),
                    "title": .string("GDP ISSUANCE KJFK"),
                    "text": .string("Ground delay program in effect."),
                    "plain_english": .string("JFK arrivals are being held at their departure airports."),
                    "effective_start": .string("2026-09-12T14:00:00Z"),
                    "effective_end": .string("2026-09-12T22:00:00Z"),
                ]),
            ]),
            "meter_fixes": .array([
                .object([
                    "flight_id": .string("DAL244"),
                    "fix": .string("LENDY"),
                    "eta": .string("2026-09-12T18:10:00Z"),
                ]),
            ]),
            "tfdm": .object([
                "supported": .bool(true),
                "airport": .string("KEWR"),
                "queue_wait_minutes": .number(18),
                "taxi_out_minutes": .number(24),
                "runway_departure_earliest": .string("2026-09-12T16:40:00Z"),
                "runway_assigned": .string("22R"),
            ]),
        ])
        let brief = FlowBriefEnvelope.parse(json)
        #expect(brief.hasContent)
        #expect(brief.orderedEffects.count == 1)
        #expect(brief.orderedEffects[0].severityCode == "INFO")
        #expect(brief.advisories?.first?.displayLine == "JFK arrivals are being held at their departure airports.")
        #expect(brief.meterFixes?.first?.fix == "LENDY")
        #expect(brief.tfdm?.queueWaitMinutes?.intValue == 18)
        #expect(brief.tfdm?.hasContent == true)
    }

    @Test func flowBriefComposesFromSwimHelpers() {
        let tfms = SwimEnvelope(feed: "tfms-flow", timestamp: nil,
                                totalRawMessages: 2, filteredResults: 1,
                                results: [
                                    .object([
                                        "type": .string("tfms_advisory"),
                                        "title": .string("GS LGA"),
                                        "text": .string("Ground stop for LGA arrivals."),
                                    ]),
                                ],
                                error: nil, detail: nil)
        let composed = FlowBriefEnvelope.compose(tfms: tfms, tbfm: nil, tfdm: nil,
                                                 flight: "B6156", origin: "KJFK", dest: "KLGA")
        #expect(composed.composedFromHelpers == true)
        #expect(composed.hasContent)
        #expect(composed.advisories?.first?.displayLine == "GS LGA")
    }

    @Test func flowBriefEmptyIsNotContent() {
        let empty = FlowBriefEnvelope.parse(.object([
            "effects": .array([]),
            "advisories": .array([]),
        ]))
        #expect(!empty.hasContent)
    }

    @Test func itwsParsesMicroburstAndGustFront() {
        let swim = SwimEnvelope(feed: "itws", timestamp: nil,
                                totalRawMessages: 3, filteredResults: 2,
                                results: [
                                    .object([
                                        "alert_type": .string("MICROBURST"),
                                        "airport": .string("KJFK"),
                                        "product_name": .string("MB Alert"),
                                    ]),
                                    .object([
                                        "alert_type": .string("GUST_FRONT"),
                                        "airport": .string("KJFK"),
                                        "gust_front": .object([
                                            "minutes_to_impact": .string("12"),
                                        ]),
                                    ]),
                                    .object([
                                        "type": .string("itws_alert"),
                                        "product_name": .string("routine product"),
                                    ]),
                                ],
                                error: nil, detail: nil)
        let alerts = ItwsAlert.parse(from: swim)
        #expect(alerts.count == 2)
        #expect(alerts[0].kindCode == "MICROBURST")
        #expect(alerts[1].headline.contains("12"))
    }

    @Test func modelGuidanceHidesWhenEmpty() {
        let empty = ModelGuidanceEnvelope.parse(.object([
            "source": .string("open-meteo"),
            "airports": .object([:]),
        ]))
        #expect(!empty.hasContent)

        let populated = ModelGuidanceEnvelope.parse(.object([
            "source": .string("open-meteo"),
            "model": .string("gfs_seamless"),
            "airports": .object([
                "KJFK": .object([
                    "temperature_c": .number(18),
                    "wind_speed_kts": .number(12),
                    "gust_kts": .number(20),
                    "precipitation_mm": .number(0.2),
                ]),
            ]),
        ]), icaos: ["KJFK"])
        #expect(populated.hasContent)
        #expect(populated.airports.first?.temperatureC == 18)
        #expect(populated.airports.first?.line.contains("18°C") == true)
    }

    @Test func filedRouteExtractsWaypointsAndString() {
        let string = JSONValue.string("JFK GREKO LENDY")
        #expect(string.filedRouteString == "JFK GREKO LENDY")

        let object = JSONValue.object([
            "waypoints": .array([.string("JFK"), .string("GREKO"), .string("LENDY")]),
        ])
        #expect(object.filedRouteString == "JFK GREKO LENDY")

        let nested = JSONValue.object(["route": .string("DCT GREKO")])
        #expect(nested.filedRouteString == "DCT GREKO")
    }

    private func decodeAtfm(_ object: [String: Any]) throws -> AtfmEnvelope {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(AtfmEnvelope.self, from: data)
    }
}

/// `simple_summary` is optional and loss-tolerant: older backends omit it,
/// and a future backend may send a string or a loosely-keyed object.
struct SimpleSummaryParseTests {

    @Test func missingAndEmptyAreNil() {
        #expect(BriefSimpleSummary.parse(nil) == nil)
        #expect(BriefSimpleSummary.parse(.null) == nil)
        #expect(BriefSimpleSummary.parse(.string("   ")) == nil)
        #expect(BriefSimpleSummary.parse(.object([:])) == nil)
        #expect(BriefSimpleSummary.parse(.array([])) == nil)
        #expect(BriefSimpleSummary.parse(.number(1)) == nil)
    }

    @Test func stringPayloadBecomesBody() {
        let parsed = BriefSimpleSummary.parse(.string("Gate around 8:43 AM."))
        #expect(parsed?.whatIThink == "Gate around 8:43 AM.")
        #expect(parsed?.hasContent == true)
    }

    @Test func objectPrefersCanonicalKeys() {
        let parsed = BriefSimpleSummary.parse(.object([
            "headline": .string("On track"),
            "what_i_think": .string("I expect a 9:05 AM takeoff."),
            "confidence_note": .string("Too early to be sure."),
            "risk": .string("LOW"),
            "confidence": .string("LOW"),
        ]))
        #expect(parsed?.headline == "On track")
        #expect(parsed?.whatIThink == "I expect a 9:05 AM takeoff.")
        #expect(parsed?.confidenceNote == "Too early to be sure.")
        #expect(parsed?.risk == "LOW")
        #expect(parsed?.confidence == "LOW")
    }

    @Test func alternateKeysStillDecode() {
        let parsed = BriefSimpleSummary.parse(.object([
            "title": .string("May be late"),
            "body": .string("Weather at the origin."),
            "caveat": .string("This can still change."),
        ]))
        #expect(parsed?.headline == "May be late")
        #expect(parsed?.whatIThink == "Weather at the origin.")
        #expect(parsed?.confidenceNote == "This can still change.")
    }
}

struct BriefEnvelopeSimpleSummaryTests {

    @Test func olderBriefWithoutSimpleSummaryStillDecodes() throws {
        let json = """
        {"flight":"DL244","verdict":{"departure_risk":"LOW","confidence":"LOW"}}
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(BriefEnvelope.self, from: json)
        #expect(envelope.simpleSummary == nil)
        let stored = StoredBrief(envelope: envelope)
        #expect(stored.simpleSummary == nil)
        #expect(stored.isNeutral)
    }

    @Test func objectSurvivesIntoStoredBrief() throws {
        let stored = try Self.brief([
            "flight": "DL244",
            "simple_summary": [
                "headline": "Looking on time",
                "what_i_think": "Gate around 8:43 AM.",
            ],
        ])
        #expect(stored.simpleSummary?.headline == "Looking on time")
        #expect(stored.simpleSummary?.whatIThink == "Gate around 8:43 AM.")
    }

    @Test func unexpectedShapeDoesNotFailTheBrief() throws {
        let stored = try Self.brief([
            "flight": "DL244",
            "verdict": ["departure_risk": "LOW", "confidence": "MEDIUM"],
            "simple_summary": [1, 2, 3],
        ])
        #expect(stored.simpleSummary == nil)
        #expect(stored.riskLevel == .low)
    }

    static func brief(_ object: [String: Any]) throws -> StoredBrief {
        let data = try JSONSerialization.data(withJSONObject: object)
        return StoredBrief(envelope: try JSONDecoder().decode(BriefEnvelope.self, from: data))
    }
}

struct SimplePredictionComposerTests {

    @Test func usesServerSummaryWhenPresent() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "simple_summary": [
                "headline": "Server headline",
                "what_i_think": "Server body",
                "confidence_note": "Server caveat",
            ],
        ])
        let prediction = SimplePredictionComposer.prediction(brief: stored, live: nil)
        #expect(prediction.fromServer)
        #expect(prediction.headline == "Server headline")
        #expect(prediction.body == "Server body")
        #expect(prediction.confidenceNote == "Server caveat")
    }

    @Test func fallbackComposesTimesAndDoesNotReassureLowLow() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "verdict": ["departure_risk": "LOW", "confidence": "LOW"],
            "branch_classification": ["branch": "NOT_APPLICABLE"],
            "predicted_times": [
                "gate_departure": [
                    "local_display": "8:43 AM EDT",
                    "timezone": "America/New_York",
                    "status": "ESTIMATED",
                ],
                "takeoff": [
                    "local_display": "9:05 AM EDT",
                    "timezone": "America/New_York",
                    "status": "ESTIMATED",
                ],
                "gate_arrival": [
                    "local_display": "11:22 AM PDT",
                    "timezone": "America/Los_Angeles",
                    "status": "ESTIMATED",
                ],
            ],
        ])
        #expect(stored.isNeutral)
        let prediction = SimplePredictionComposer.prediction(brief: stored, live: nil)
        #expect(!prediction.fromServer)
        #expect(prediction.headline == "Nothing looks delayed yet")
        #expect(prediction.body.contains("8:43 AM EDT"))
        #expect(prediction.body.contains("9:05 AM EDT"))
        #expect(prediction.body.contains("11:22 AM PDT"))

        let risk = SimplePredictionComposer.risk(brief: stored, live: nil)
        #expect(risk.tone == .neutral)
        #expect(risk.label == "Too early to say")
        #expect(risk.chipTone == .neutral)

        let card = SimplePredictionComposer.cardStatus(
            brief: stored, live: nil, phase: stored.phase, leg: nil)
        #expect(card.text == "Scheduled")
        #expect(card.tone == .neutral)
    }

    @Test func highRiskIsAlertNotGreen() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "verdict": ["departure_risk": "HIGH", "confidence": "HIGH"],
        ])
        let risk = SimplePredictionComposer.risk(brief: stored, live: nil)
        #expect(risk.tone == .alert)
        #expect(risk.label == "Expect delays")
        let prediction = SimplePredictionComposer.prediction(brief: stored, live: nil)
        #expect(prediction.headline.contains("late"))
    }

    @Test func confidentLowMaySayOnTimeOnTheCard() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "verdict": ["departure_risk": "LOW", "confidence": "HIGH"],
        ])
        #expect(!stored.isNeutral)
        let risk = SimplePredictionComposer.risk(brief: stored, live: nil)
        #expect(risk.tone == .ok)
        #expect(risk.label == "Looking on time")
        let card = SimplePredictionComposer.cardStatus(
            brief: stored, live: nil, phase: nil, leg: nil)
        #expect(card.text == "On time")
    }

    @Test func statusOnlyLowNeverSaysOnTime() throws {
        let json = """
        {"verdict":{"departure_risk":"LOW","confidence":"LOW","scope":"status_only"},
         "fetched_at":"2026-09-12T12:00:00Z","refresh_after_seconds":120}
        """.data(using: .utf8)!
        let live = StoredLive(envelope: try JSONDecoder().decode(LiveEnvelope.self, from: json))
        let risk = SimplePredictionComposer.risk(brief: nil, live: live)
        #expect(risk.tone == .neutral)
        #expect(risk.label == "Status looks routine")

        let card = SimplePredictionComposer.cardStatus(
            brief: nil, live: live, phase: nil, leg: nil)
        #expect(card.text == "Scheduled")
        #expect(card.tone == .neutral)
    }

    @Test func airborneCardSaysInTheAir() {
        let phase = BriefPhase(phase: "AIRBORNE", phaseLabel: "Airborne",
                               phaseDetail: nil, elapsedInPhaseMin: 40,
                               nextEvent: "gate_arrival", nextEventLabel: "Arrival",
                               nextEventLocalDisplay: "11:22 AM PDT",
                               nextEventBasis: nil, nextEventStatus: "ESTIMATED",
                               nextEventOverdue: false, minutesToNextEvent: 90)
        let card = SimplePredictionComposer.cardStatus(
            brief: nil, live: nil, phase: phase, leg: nil)
        #expect(card.text == "In the air")
        #expect(card.tone == .info)
    }

    @Test func emptyStateIsNeutralScheduled() {
        let risk = SimplePredictionComposer.risk(brief: nil, live: nil)
        #expect(risk.tone == .neutral)
        let card = SimplePredictionComposer.cardStatus(
            brief: nil, live: nil, phase: nil, leg: nil)
        #expect(card.text == "Scheduled")
    }
}

/// Missing UserDefaults key = Pro, so existing installs keep today's UI.
struct DisplayModePersistenceTests {

    @Test func missingKeyIsPro() {
        let suite = "pft.test.displayMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(AppDisplayMode.load(from: defaults) == .pro)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func persistsAndReloadsSimple() {
        let suite = "pft.test.displayMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        AppDisplayMode.simple.persist(to: defaults)
        #expect(AppDisplayMode.load(from: defaults) == .simple)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func unknownValueFallsBackToPro() {
        let suite = "pft.test.displayMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("nerd", forKey: AppDisplayMode.defaultsKey)
        #expect(AppDisplayMode.load(from: defaults) == .pro)
        defaults.removePersistentDomain(forName: suite)
    }
}

/// v1.13 story layer: `status`, `impactMinutes`, `causes[]`, `outlook`.
/// Optional / loss-tolerant so older backends and persisted snapshots decode.
struct StoryLayerDecodeTests {

    @Test func olderBriefWithoutStoryKeysStillDecodes() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "flight": "DL244",
            "verdict": ["departure_risk": "LOW", "confidence": "LOW"],
        ])
        #expect(stored.status == nil)
        #expect(stored.impactMinutes == nil)
        #expect(stored.causes == nil)
        #expect(stored.outlook == nil)
        #expect(FlightStory.resolve(brief: stored, live: nil).hasContent == false)
    }

    @Test func camelCaseStorySurvivesIntoStoredBrief() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "flight": "DL244",
            "status": [
                "code": "DELAYED",
                "label": "Delayed 16m",
                "phase": "PRE_GATE",
            ],
            "impactMinutes": 16,
            "causes": [
                [
                    "label": "FAA takeoff slot",
                    "why": "The FAA assigned a takeoff time — expect to wait.",
                    "severity": "ACTION",
                    "source": "swim_tfms",
                ],
                [
                    "label": "GDP at JFK",
                    "why": "Arrival metering into the airport — may push your wheels-up",
                    "severity": "INFO",
                    "source": "faa_status",
                ],
            ],
            "outlook": ["applicable": false],
        ])
        #expect(stored.status?.statusCode == "DELAYED")
        #expect(stored.status?.displayLabel == "Delayed 16m")
        #expect(stored.impactMinutes == 16)
        #expect(stored.causes?.count == 2)
        #expect(stored.causes?.first?.label == "FAA takeoff slot")
        #expect(stored.causes?.first?.severityLabel == "Needs attention")
        #expect(stored.outlook?.isApplicable == false)
    }

    @Test func snakeCaseImpactAndRiskStillDecode() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "impact_minutes": 42,
            "outlook": [
                "applicable": true,
                "risk_level": "HIGH",
                "confidence": "LOW",
                "headline": "High delay risk · thunderstorms",
                "causes": [
                    [
                        "label": "Thunderstorms around departure",
                        "why": "This is a forecast, not a delay assignment yet.",
                        "severity": "ACTION",
                        "source": "taf",
                    ],
                ],
            ],
        ])
        #expect(stored.impactMinutes == 42)
        #expect(stored.outlook?.isApplicable == true)
        #expect(stored.outlook?.risk == .high)
        #expect(stored.outlook?.headline == "High delay risk · thunderstorms")
    }

    @Test func liveEnvelopeStoryIsOptional() throws {
        let json = """
        {"fetched_at":"2026-09-12T12:00:00Z","refresh_after_seconds":120,
         "status":{"code":"ON_TIME","label":"On time","phase":"PRE_GATE"},
         "impactMinutes":2,
         "causes":[],
         "outlook":{"applicable":false}}
        """.data(using: .utf8)!
        let live = StoredLive(envelope: try JSONDecoder().decode(LiveEnvelope.self, from: json))
        #expect(live.status?.statusCode == "ON_TIME")
        #expect(live.impactMinutes == 2)
        #expect(live.outlook?.isApplicable == false)

        let older = """
        {"fetched_at":"2026-09-12T12:00:00Z","refresh_after_seconds":120}
        """.data(using: .utf8)!
        let oldLive = StoredLive(envelope: try JSONDecoder().decode(LiveEnvelope.self, from: older))
        #expect(oldLive.status == nil)
        #expect(oldLive.outlook == nil)
    }
}

struct FlightStoryResolverTests {

    @Test func outlookApplicableIsTheHero() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "status": [
                "code": "UNKNOWN",
                "label": "Too early to call",
                "phase": "PRE_GATE",
            ],
            "causes": [],
            "outlook": [
                "applicable": true,
                "riskLevel": "MODERATE",
                "confidence": "LOW",
                "headline": "Elevated delay risk · thunderstorms",
                "causes": [
                    [
                        "label": "Thunderstorms around departure",
                        "why": "Thunderstorms in this window are the usual trigger.",
                        "severity": "ACTION",
                        "source": "taf",
                    ],
                ],
            ],
        ])
        let story = FlightStory.resolve(brief: stored, live: nil)
        #expect(story.usesOutlook)
        #expect(story.outlook?.headline == "Elevated delay risk · thunderstorms")
        #expect(story.causes.first?.label == "Thunderstorms around departure")
        #expect(story.impactMinutes == nil)
        #expect(story.status?.displayLabel == "Too early to call")

        let prediction = SimplePredictionComposer.prediction(brief: stored, live: nil)
        #expect(prediction.fromServer)
        #expect(prediction.headline == "Elevated delay risk · thunderstorms")
        #expect(prediction.body.contains("Thunderstorms"))

        let card = SimplePredictionComposer.cardStatus(
            brief: stored, live: nil, phase: stored.phase, leg: nil)
        #expect(card.text == "Too early to call")
        #expect(card.tone == .watch)
    }

    @Test func liveNearUsesStatusAndCauses() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "status": [
                "code": "DELAYED",
                "label": "Delayed 16m",
                "phase": "PRE_GATE",
            ],
            "impactMinutes": 16,
            "causes": [
                [
                    "label": "FAA takeoff slot",
                    "why": "The FAA assigned a takeoff time — expect to wait.",
                    "severity": "ACTION",
                    "source": "swim_tfms",
                ],
            ],
            "outlook": ["applicable": false],
        ])
        let story = FlightStory.resolve(brief: stored, live: nil)
        #expect(!story.usesOutlook)
        #expect(story.status?.displayLabel == "Delayed 16m")
        #expect(story.impactMinutes == 16)
        #expect(story.causes.first?.label == "FAA takeoff slot")
        #expect(story.causes.first?.severityLabel == "Needs attention")

        let card = SimplePredictionComposer.cardStatus(
            brief: stored, live: nil, phase: nil, leg: nil)
        #expect(card.text == "Delayed 16m")
        #expect(card.tone == .alert)
    }

    @Test func liveOutlookApplicableFalseNeverBecomesForecast() throws {
        let json = """
        {"fetched_at":"2026-09-12T12:00:00Z","refresh_after_seconds":120,
         "status":{"code":"UNKNOWN","label":"Too early to call","phase":"PRE_GATE"},
         "outlook":{"applicable":false}}
        """.data(using: .utf8)!
        let live = StoredLive(envelope: try JSONDecoder().decode(LiveEnvelope.self, from: json))
        let story = FlightStory.resolve(brief: nil, live: live)
        #expect(!story.usesOutlook)
        #expect(story.status?.displayLabel == "Too early to call")
    }

    @Test func freshBriefOutlookWinsOverLiveTile() throws {
        let brief = try BriefEnvelopeSimpleSummaryTests.brief([
            "outlook": [
                "applicable": true,
                "riskLevel": "LOW",
                "confidence": "LOW",
                "headline": "Low delay risk on the forecast",
                "causes": [
                    [
                        "label": "Nothing worrying on the forecast",
                        "why": "No thunderstorms in the window we can see.",
                        "severity": "INFO",
                        "source": "taf",
                    ],
                ],
            ],
            "status": ["code": "UNKNOWN", "label": "Too early to call"],
        ])
        let json = """
        {"fetched_at":"2026-09-12T12:00:00Z","refresh_after_seconds":120,
         "status":{"code":"UNKNOWN","label":"Too early to call","phase":"PRE_GATE"},
         "outlook":{"applicable":false}}
        """.data(using: .utf8)!
        let live = StoredLive(envelope: try JSONDecoder().decode(LiveEnvelope.self, from: json))
        let story = FlightStory.resolve(brief: brief, live: live)
        #expect(story.usesOutlook)
        #expect(story.outlook?.headline == "Low delay risk on the forecast")
    }

    @Test func simpleSummaryStillWinsThePredictionCard() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "simple_summary": [
                "headline": "Server headline",
                "what_i_think": "Server body",
            ],
            "outlook": [
                "applicable": true,
                "riskLevel": "MODERATE",
                "headline": "Should not replace simple_summary",
                "causes": [
                    ["label": "Thunderstorms", "why": "Forecast.",
                     "severity": "ACTION", "source": "taf"],
                ],
            ],
        ])
        let prediction = SimplePredictionComposer.prediction(brief: stored, live: nil)
        #expect(prediction.headline == "Server headline")
        #expect(prediction.body == "Server body")
    }

    @Test func severityIsNamedNotColorOnly() {
        let action = StoryCause(label: "Ground stop at LGA", why: "Nothing can land.",
                                severity: "ACTION", source: "faa_status")
        let watch = StoryCause(label: "Inbound turn is tight", why: "Any further slip transfers.",
                               severity: "WATCH", source: "equipment_chain")
        let info = StoryCause(label: "GDP at JFK", why: "Arrival metering.",
                              severity: "INFO", source: "faa_status")
        #expect(action.severityLabel == "Needs attention")
        #expect(watch.severityLabel == "Watch")
        #expect(info.severityLabel == "Context")
    }

    @Test func causesKeepServerOrder() throws {
        let stored = try BriefEnvelopeSimpleSummaryTests.brief([
            "causes": [
                ["label": "A", "why": "first", "severity": "ACTION", "source": "taxi"],
                ["label": "B", "why": "second", "severity": "WATCH", "source": "faa_status"],
                ["label": "C", "why": "third", "severity": "INFO", "source": "atfm"],
            ],
            "outlook": ["applicable": false],
            "status": ["code": "DELAYED", "label": "Delayed"],
        ])
        let labels = FlightStory.resolve(brief: stored, live: nil).orderedCauses.map { $0.label }
        #expect(labels == ["A", "B", "C"])
    }
}
