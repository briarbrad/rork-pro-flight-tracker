import Foundation
import SwiftUI

/// Traveler-facing operational status from `/api/brief` and `/api/flight/live`
/// (`status` in v1.13). Optional on older backends.
///
/// `code`: DELAYED / ON_TIME / EARLY / CANCELLED / ARRIVED / DIVERTED / UNKNOWN.
/// Far-out horizons are UNKNOWN ("Too early to call") — never a fake ON_TIME.
nonisolated struct StoryStatus: Codable, Hashable, Sendable {
    var code: String?
    var label: String?
    var phase: String?

    var statusCode: String { (code ?? "UNKNOWN").uppercased() }

    var displayLabel: String? {
        guard let label, !label.isEmpty else { return nil }
        return label
    }

    var chipTone: ChipTone {
        switch statusCode {
        case "DELAYED", "CANCELLED", "DIVERTED": return .alert
        case "EARLY", "ON_TIME", "ARRIVED": return .ok
        default: return .neutral
        }
    }
}

/// One traveler-facing cause row (`causes[]` / `outlook.causes[]`).
/// Ordered ACTION → WATCH → INFO server-side — the client never re-ranks.
nonisolated struct StoryCause: Codable, Hashable, Sendable {
    var label: String?
    var why: String?
    var severity: String?
    var source: String?

    var severityCode: String { (severity ?? "INFO").uppercased() }

    /// Spoken severity — never color-only meaning.
    var severityLabel: String {
        switch severityCode {
        case "ACTION": return "Needs attention"
        case "WATCH": return "Watch"
        default: return "Context"
        }
    }

    var chipTone: ChipTone {
        switch severityCode {
        case "ACTION": return .alert
        case "WATCH": return .watch
        default: return .neutral
        }
    }

    var icon: String {
        switch severityCode {
        case "ACTION": return "octagon-alert"
        case "WATCH": return "eye"
        default: return "info"
        }
    }

    var hasContent: Bool {
        !(label ?? "").isEmpty || !(why ?? "").isEmpty
    }
}

/// Far-out forecast block. Show this as the hero only when `applicable == true`.
/// `/api/flight/live` always sends `{applicable: false}`.
nonisolated struct StoryOutlook: Codable, Hashable, Sendable {
    var applicable: Bool?
    var riskLevel: String?
    var confidence: String?
    var headline: String?
    var causes: [StoryCause]?

    enum CodingKeys: String, CodingKey {
        case applicable, confidence, headline, causes
        case riskLevel
        case risk_level
    }

    init(applicable: Bool? = nil,
         riskLevel: String? = nil,
         confidence: String? = nil,
         headline: String? = nil,
         causes: [StoryCause]? = nil) {
        self.applicable = applicable
        self.riskLevel = riskLevel
        self.confidence = confidence
        self.headline = headline
        self.causes = causes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applicable = try container.decodeIfPresent(Bool.self, forKey: .applicable)
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
        headline = try container.decodeIfPresent(String.self, forKey: .headline)
        causes = try container.decodeIfPresent([StoryCause].self, forKey: .causes)
        riskLevel = try container.decodeIfPresent(String.self, forKey: .riskLevel)
            ?? container.decodeIfPresent(String.self, forKey: .risk_level)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(applicable, forKey: .applicable)
        try container.encodeIfPresent(riskLevel, forKey: .riskLevel)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(headline, forKey: .headline)
        try container.encodeIfPresent(causes, forKey: .causes)
    }

    /// The only switch — do not infer a forecast from horizon or status.
    var isApplicable: Bool { applicable == true }

    var orderedCauses: [StoryCause] { (causes ?? []).filter(\.hasContent) }

    var risk: RiskLevel? {
        riskLevel.flatMap { RiskLevel(rawValue: $0.uppercased()) }
    }

    var isLowConfidence: Bool { confidence?.uppercased() == "LOW" }
}

/// Resolved flight-screen story. Bind these fields; do not re-derive.
nonisolated struct FlightStory: Hashable, Sendable {
    enum Kind: String, Sendable {
        /// Far-out forecast: risk + confidence + outlook causes.
        case outlook
        /// Live / near: status.label + impactMinutes + operational causes.
        case live
    }

    var kind: Kind
    var status: StoryStatus?
    var impactMinutes: Int?
    var outlook: StoryOutlook?
    var causes: [StoryCause]

    var usesOutlook: Bool { kind == .outlook }

    var hasContent: Bool {
        status?.displayLabel != nil
            || impactMinutes != nil
            || !(outlook?.headline ?? "").isEmpty
            || !causes.isEmpty
    }

    /// Server order, already ACTION → WATCH → INFO.
    var orderedCauses: [StoryCause] { causes.filter(\.hasContent) }

    var hasCauses: Bool { !orderedCauses.isEmpty }

    /// One-rule resolver: outlook when `applicable == true` on a fresh brief;
    /// otherwise live/near status + impact + causes. Live layer wins the
    /// live story once it has arrived (it always ships applicable: false).
    static func resolve(brief: StoredBrief?, live: StoredLive?) -> FlightStory {
        if let brief, !brief.isStale, brief.outlook?.isApplicable == true {
            return FlightStory(
                kind: .outlook,
                status: brief.status ?? live?.status,
                impactMinutes: nil,
                outlook: brief.outlook,
                causes: brief.outlook?.orderedCauses ?? [])
        }

        if let live, live.hasStoryFields {
            return FlightStory(
                kind: .live,
                status: live.status,
                impactMinutes: live.impactMinutes,
                outlook: live.outlook,
                causes: live.causes ?? [])
        }

        if let brief {
            if brief.outlook?.isApplicable == true, !brief.isStale {
                return FlightStory(
                    kind: .outlook,
                    status: brief.status,
                    impactMinutes: brief.impactMinutes,
                    outlook: brief.outlook,
                    causes: brief.outlook?.orderedCauses ?? [])
            }
            return FlightStory(
                kind: .live,
                status: brief.status,
                impactMinutes: brief.impactMinutes,
                outlook: brief.outlook,
                causes: brief.causes ?? [])
        }

        return FlightStory(kind: .live, status: nil, impactMinutes: nil,
                           outlook: nil, causes: [])
    }
}

extension StoredBrief {
    var hasStoryFields: Bool {
        status != nil || impactMinutes != nil || !(causes ?? []).isEmpty
            || outlook != nil
    }

    var hasStoryCauses: Bool {
        !(causes ?? []).isEmpty || outlook?.isApplicable == true
    }
}

extension StoredLive {
    var hasStoryFields: Bool {
        status != nil || impactMinutes != nil || !(causes ?? []).isEmpty
            || outlook != nil
    }
}
