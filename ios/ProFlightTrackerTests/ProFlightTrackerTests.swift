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
