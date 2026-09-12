import Foundation

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
}

/// One traveler-facing cause row (`causes[]` / `outlook.causes[]`).
/// Ordered ACTION → WATCH → INFO server-side — the client never re-ranks.
nonisolated struct StoryCause: Codable, Hashable, Sendable {
    var label: String?
    var why: String?
    var severity: String?
    var source: String?

    var severityCode: String { (severity ?? "INFO").uppercased() }

    /// Spoken severity for VoiceOver — chrome never names this on screen.
    var severitySpoken: String {
        switch severityCode {
        case "ACTION": return "Needs attention"
        case "WATCH": return "Watch"
        default: return "Context"
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
}

/// Locked flight-screen story. One switch, nothing looser:
/// - `outlook.applicable` → hero = `outlook.headline`, causes = `outlook.causes`
/// - else → hero = `simple_summary`, sub = `status.label` + `impactMinutes`,
///   causes = `causes`
nonisolated struct FlightStory: Hashable, Sendable {
    enum Kind: String, Sendable {
        case outlook
        case summary
    }

    var kind: Kind
    var simpleSummary: BriefSimpleSummary?
    var status: StoryStatus?
    var impactMinutes: Int?
    var outlook: StoryOutlook?
    var causes: [StoryCause]

    var usesOutlook: Bool { kind == .outlook }

    /// Server order, already ACTION → WATCH → INFO.
    var orderedCauses: [StoryCause] { causes.filter(\.hasContent) }

    var hasCauses: Bool { !orderedCauses.isEmpty }

    var heroHeadline: String? {
        if usesOutlook {
            let text = outlook?.headline?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false) ? text : nil
        }
        return simpleSummary?.headline
    }

    var heroBody: String? {
        usesOutlook ? nil : simpleSummary?.whatIThink
    }

    var hasContent: Bool {
        if usesOutlook {
            return heroHeadline != nil || hasCauses
        }
        return simpleSummary?.hasContent == true
            || status?.displayLabel != nil
            || impactMinutes != nil
            || hasCauses
    }

    /// `status.label` + `impactMinutes` for the else-branch subtitle.
    var statusSubline: String? {
        guard !usesOutlook else { return nil }
        var parts: [String] = []
        if let label = status?.displayLabel { parts.append(label) }
        if let minutes = impactMinutes {
            if minutes > 0 {
                parts.append("+\(minutes) min")
            } else if minutes < 0 {
                parts.append("\(minutes) min")
            } else {
                parts.append("0 min")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `outlook.applicable` is the only switch. Live always ships false.
    /// Else-branch fields: `simple_summary` prefers the brief (full
    /// prediction); `status` / `impactMinutes` / `causes` prefer live when
    /// that pull actually sent the keys (including an empty cause list).
    static func resolve(brief: StoredBrief?, live: StoredLive?) -> FlightStory {
        if let outlook = brief?.outlook, outlook.isApplicable {
            return FlightStory(
                kind: .outlook,
                simpleSummary: nil,
                status: brief?.status ?? live?.status,
                impactMinutes: nil,
                outlook: outlook,
                causes: outlook.orderedCauses)
        }

        let causes: [StoryCause]
        if let liveCauses = live?.causes {
            causes = liveCauses
        } else {
            causes = brief?.causes ?? []
        }

        return FlightStory(
            kind: .summary,
            simpleSummary: brief?.simpleSummary ?? live?.simpleSummary,
            status: live?.status ?? brief?.status,
            impactMinutes: live?.impactMinutes ?? brief?.impactMinutes,
            outlook: brief?.outlook ?? live?.outlook,
            causes: causes)
    }
}

extension StoredBrief {
    var hasStoryFields: Bool {
        status != nil || impactMinutes != nil || !(causes ?? []).isEmpty
            || outlook != nil
    }
}

extension StoredLive {
    var hasStoryFields: Bool {
        status != nil || impactMinutes != nil || !(causes ?? []).isEmpty
            || outlook != nil
    }
}
