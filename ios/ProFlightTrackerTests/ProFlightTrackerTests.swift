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
}
