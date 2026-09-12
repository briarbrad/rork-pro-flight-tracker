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
