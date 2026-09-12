import Foundation
import SwiftUI

/// Passenger-facing prediction assembled from an optional backend
/// `simple_summary` or, when that field is absent, from the deterministic
/// verdict + predicted times + a short narrative snippet.
///
/// Decode is loss-tolerant: older backends omit the key, and a future
/// backend may send a string or a loosely-keyed object. Unexpected JSON
/// never fails the enclosing brief / live envelope.
nonisolated struct BriefSimpleSummary: Codable, Hashable, Sendable {
    var headline: String?
    var whatIThink: String?
    var confidenceNote: String?
    var risk: String?
    var confidence: String?

    var hasContent: Bool {
        [headline, whatIThink, confidenceNote].contains { !($0 ?? "").isEmpty }
    }

    /// Parses a `simple_summary` JSON value. `nil` / empty / unknown shapes
    /// produce `nil` so the composer can fall back.
    static func parse(_ raw: JSONValue?) -> BriefSimpleSummary? {
        guard let raw else { return nil }
        switch raw {
        case .null:
            return nil
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return BriefSimpleSummary(headline: nil, whatIThink: trimmed,
                                      confidenceNote: nil, risk: nil, confidence: nil)
        case .object(let dict):
            let summary = BriefSimpleSummary(
                headline: firstString(in: dict, keys: ["headline", "title", "summary"]),
                whatIThink: firstString(in: dict, keys: [
                    "what_i_think", "whatIThink", "prediction", "body", "text",
                ]),
                confidenceNote: firstString(in: dict, keys: [
                    "confidence_note", "confidenceNote", "caveat", "note",
                ]),
                risk: firstString(in: dict, keys: ["risk", "departure_risk", "departureRisk"]),
                confidence: firstString(in: dict, keys: ["confidence"]))
            return summary.hasContent || summary.risk != nil ? summary : nil
        default:
            return nil
        }
    }

    private static func firstString(in dict: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

/// Ready-to-render prediction for Simple mode. The kicker is always
/// "Based on what I know" — the headline and body change with the data.
nonisolated struct SimplePrediction: Hashable, Sendable {
    let headline: String
    let body: String
    let confidenceNote: String?
    /// True when the prose came from backend `simple_summary`.
    let fromServer: Bool
}

/// One risk / confidence treatment for Simple mode. Never paints LOW/LOW
/// (or a status-only LOW) as reassuring green "on time / low risk".
nonisolated struct SimpleRiskTreatment: Hashable, Sendable {
    enum Tone: String, Sendable {
        case ok, watch, alert, neutral
    }

    let label: String
    let detail: String
    let tone: Tone

    var chipTone: ChipTone {
        switch tone {
        case .ok: return .ok
        case .watch: return .watch
        case .alert: return .alert
        case .neutral: return .neutral
        }
    }

    var icon: String {
        switch tone {
        case .ok: return "shield-check"
        case .watch: return "triangle-alert"
        case .alert: return "octagon-alert"
        case .neutral: return "hourglass"
        }
    }
}

/// Builds the Simple-mode prediction and risk copy from the same snapshot
/// the Pro layout already has. No extra network.
nonisolated enum SimplePredictionComposer {

    static func prediction(brief: StoredBrief?,
                           live: StoredLive?,
                           zones: FlightZones = .unknown) -> SimplePrediction {
        if let summary = brief?.simpleSummary ?? live?.simpleSummary, summary.hasContent {
            return SimplePrediction(
                headline: summary.headline ?? defaultHeadline(brief: brief, live: live),
                body: summary.whatIThink ?? composedBody(brief: brief, live: live, zones: zones),
                confidenceNote: summary.confidenceNote ?? composedConfidenceNote(brief: brief),
                fromServer: true)
        }
        let story = FlightStory.resolve(brief: brief, live: live)
        if story.usesOutlook, let headline = story.outlook?.headline, !headline.isEmpty {
            return SimplePrediction(
                headline: headline,
                body: outlookBody(story, fallback: composedBody(brief: brief, live: live, zones: zones)),
                confidenceNote: outlookConfidenceNote(story) ?? composedConfidenceNote(brief: brief),
                fromServer: true)
        }
        return SimplePrediction(
            headline: story.status?.displayLabel ?? defaultHeadline(brief: brief, live: live),
            body: composedBody(brief: brief, live: live, zones: zones),
            confidenceNote: composedConfidenceNote(brief: brief),
            fromServer: story.status != nil)
    }

    static func risk(brief: StoredBrief?, live: StoredLive?) -> SimpleRiskTreatment {
        if let brief {
            if let liveLevel = live?.riskLevel, overridesBrief(brief, liveLevel: liveLevel) {
                return treatment(forLive: liveLevel)
            }
            return treatment(forBrief: brief)
        }
        if let liveLevel = live?.riskLevel {
            return treatment(forLive: liveLevel)
        }
        return SimpleRiskTreatment(
            label: "Checking this flight",
            detail: "I'll have a clearer picture once the first assessment lands.",
            tone: .neutral)
    }

    /// Watchlist / trip-card chip — one status, no signal clutter.
    /// Prefers backend `status.label`. LOW/LOW and "no brief yet" say
    /// "Scheduled", never "On time". Outlook-applicable stays "Too early
    /// to call" (or the server label) — never a fake green on-time.
    static func cardStatus(brief: StoredBrief?,
                           live: StoredLive?,
                           phase: BriefPhase?,
                           leg: AeroFlight?) -> (text: String, tone: ChipTone) {
        if phase?.isCancelled == true || leg?.cancelled == true {
            return ("Cancelled", .alert)
        }
        if phase?.isOver == true {
            return ("Arrived", .ok)
        }
        switch phase?.code {
        case "AIRBORNE": return ("In the air", .info)
        case "TAXI_OUT", "TAXI_IN": return ("Taxiing", .watch)
        default: break
        }

        let story = FlightStory.resolve(brief: brief, live: live)
        if let label = story.status?.displayLabel {
            if story.usesOutlook {
                if let risk = story.outlook?.risk, risk.rank > RiskLevel.low.rank {
                    return (label, ChipTone.from(risk))
                }
                return (label, .neutral)
            }
            if story.status?.statusCode == "ON_TIME" {
                return (label, .ok)
            }
            return (label, story.status?.chipTone ?? .neutral)
        }

        let treatment = risk(brief: brief, live: live)
        switch treatment.tone {
        case .alert: return (treatment.label, .alert)
        case .watch: return (treatment.label, .watch)
        case .ok: return ("On time", .ok)
        case .neutral:
            return ("Scheduled", .neutral)
        }
    }

    // MARK: - Headline / body

    private static func defaultHeadline(brief: StoredBrief?, live: StoredLive?) -> String {
        let treatment = risk(brief: brief, live: live)
        switch treatment.tone {
        case .alert: return "I expect this flight to run late"
        case .watch: return "This one may not run on schedule"
        case .ok: return "I think this flight is on track"
        case .neutral:
            if brief == nil && live == nil {
                return "I'm still gathering a picture"
            }
            return "Nothing looks delayed yet"
        }
    }

    private static func composedBody(brief: StoredBrief?,
                                     live: StoredLive?,
                                     zones: FlightZones) -> String {
        var parts: [String] = []

        if let times = live?.predictedTimes ?? brief?.predictedTimes,
           let sentence = timesSentence(times, zones: zones) {
            parts.append(sentence)
        }

        let treatment = risk(brief: brief, live: live)
        if treatment.tone == .neutral {
            if brief == nil && live == nil {
                parts.append("I'm still gathering a picture of this flight.")
            } else {
                parts.append("Nothing in the current picture looks delayed, but that can still change.")
            }
        } else if let effect = topPassengerEffect(brief: brief, live: live) {
            parts.append(effect)
        } else if let driver = brief?.drivers.first, !driver.isEmpty {
            parts.append(driver)
        }

        if let brief, !brief.isStale,
           let outlook = NarrativeOutlook.outlookLine(from: brief.narrative) {
            parts.append(outlook)
        } else if let snippet = firstNarrativeSentence(brief?.narrative) {
            parts.append(snippet)
        }

        if parts.isEmpty {
            return "I don't have a firm prediction yet — check back closer to departure."
        }
        return uniqueSentences(parts).joined(separator: " ")
    }

    private static func outlookBody(_ story: FlightStory, fallback: String) -> String {
        let whys = story.orderedCauses.compactMap { cause -> String? in
            if let why = cause.why, !why.isEmpty { return why }
            return cause.label
        }
        if let first = whys.first, !first.isEmpty { return first }
        return fallback
    }

    private static func outlookConfidenceNote(_ story: FlightStory) -> String? {
        guard let confidence = story.outlook?.confidence, !confidence.isEmpty else {
            return nil
        }
        return "\(confidence.capitalized) confidence — a forecast, not a live delay."
    }

    private static func composedConfidenceNote(brief: StoredBrief?) -> String? {
        guard let brief else { return nil }
        if brief.isNeutral {
            return "Too early to be sure — weather and delays this far out usually change."
        }
        if brief.isLowConfidence {
            return "Low confidence: this far from departure, the picture can still move."
        }
        if let basis = brief.confidenceBasis, !basis.isEmpty {
            return basis
        }
        return "Confidence reflects how close we are to departure — not a guarantee of the exact times."
    }

    private static func timesSentence(_ times: BriefPredictedTimes, zones: FlightZones) -> String? {
        var chunks: [String] = []
        if let gate = display(times.gateDeparture, zone: zones.origin) {
            chunks.append("gate around \(gate)")
        }
        if let takeoff = display(times.takeoff, zone: zones.origin) {
            chunks.append("takeoff around \(takeoff)")
        }
        if let arrival = display(times.gateArrival, zone: zones.destination) {
            chunks.append("arrival around \(arrival)")
        }
        guard !chunks.isEmpty else { return nil }
        if chunks.count == 1 { return "I expect \(chunks[0])." }
        if chunks.count == 2 { return "I expect \(chunks[0]) and \(chunks[1])." }
        return "I expect \(chunks[0]), \(chunks[1]), and \(chunks[2])."
    }

    private static func display(_ entry: BriefPredictedTime?, zone: TimeZone?) -> String? {
        guard let entry, !entry.isUnknown else { return nil }
        let text = entry.displayTime(fallbackZone: zone)
        return text == "—" ? nil : text
    }

    private static func topPassengerEffect(brief: StoredBrief?, live: StoredLive?) -> String? {
        let effects = (brief?.isStale == false ? brief?.orderedEffects : nil)
            ?? live?.effects
            ?? brief?.orderedEffects
            ?? []
        let top = effects.first { $0.severityCode == "ACTION" }
            ?? effects.first { $0.severityCode == "WATCH" }
        guard let top else { return nil }
        return top.effect ?? top.cause
    }

    /// First prose sentence of the analyst narrative — never the whole essay.
    private static func firstNarrativeSentence(_ narrative: String?) -> String? {
        guard let narrative, !narrative.isEmpty else { return nil }
        for raw in narrative.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("**") && line.hasSuffix("**") && line.count < 80 { continue }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let end = line.firstIndex(of: ".") {
                let sentence = String(line[...end]).trimmingCharacters(in: .whitespaces)
                if sentence.count >= 24 { return sentence }
            }
            if line.count >= 24 { return line }
        }
        return nil
    }

    private static func uniqueSentences(_ parts: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for part in parts {
            let key = part.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(part)
        }
        return result
    }

    // MARK: - Risk

    private static func overridesBrief(_ brief: StoredBrief, liveLevel: RiskLevel) -> Bool {
        let briefRank = brief.riskLevel?.rank ?? 0
        guard brief.isStale else { return liveLevel.rank > briefRank }
        return liveLevel.rank != briefRank
    }

    private static func treatment(forBrief brief: StoredBrief) -> SimpleRiskTreatment {
        if brief.isTooEarly || brief.isNeutral {
            return SimpleRiskTreatment(
                label: "Too early to say",
                detail: "Nothing looks delayed yet. That is not the same as \"on time.\"",
                tone: .neutral)
        }
        switch brief.riskLevel {
        case .high:
            return SimpleRiskTreatment(
                label: "Expect delays",
                detail: confidenceDetail(brief, fallback: "Plan as if this flight will not run on schedule."),
                tone: .alert)
        case .moderate:
            return SimpleRiskTreatment(
                label: "May run late",
                detail: confidenceDetail(brief, fallback: "Worth watching — not a reason to rebook yet."),
                tone: .watch)
        case .low:
            return SimpleRiskTreatment(
                label: "Looking on time",
                detail: confidenceDetail(brief, fallback: "Based on what I can see right now — not a guarantee."),
                tone: .ok)
        case nil:
            return SimpleRiskTreatment(
                label: "Checking this flight",
                detail: "The assessment is still coming together.",
                tone: .neutral)
        }
    }

    private static func treatment(forLive level: RiskLevel) -> SimpleRiskTreatment {
        switch level {
        case .high:
            return SimpleRiskTreatment(
                label: "Expect delays",
                detail: "The latest airline status shows a real problem.",
                tone: .alert)
        case .moderate:
            return SimpleRiskTreatment(
                label: "May run late",
                detail: "The latest airline status is already slipping.",
                tone: .watch)
        case .low:
            // Status-only LOW is incomplete data — never "on time".
            return SimpleRiskTreatment(
                label: "Status looks routine",
                detail: "That's only the airline feed — not a full assessment.",
                tone: .neutral)
        }
    }

    private static func confidenceDetail(_ brief: StoredBrief, fallback: String) -> String {
        if brief.isLowConfidence {
            return "Low confidence this far out — the picture can still move."
        }
        if let basis = brief.confidenceBasis, !basis.isEmpty { return basis }
        return fallback
    }
}
