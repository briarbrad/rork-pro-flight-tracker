import Foundation

nonisolated enum NarrativeError: LocalizedError {
    case notConfigured
    case emptyResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI narrative is not configured."
        case .emptyResponse: return "The narrative came back empty."
        case .http(let code):
            switch code {
            case 401: return "AI features are currently unavailable."
            case 402: return "AI features are temporarily unavailable."
            case 429: return "Too many requests — try again in a moment."
            default: return "Narrative service error (\(code))."
            }
        }
    }
}

/// Turns the backend's precomputed brief facts into a short plain-English
/// narrative. The AI provider call happens server-side (POST /api/narrative)
/// so no AI secret ever ships in the app bundle. This is an enhancement
/// layer only — the deterministic verdict renders with or without it.
nonisolated enum NarrativeService {
    /// Sends the backend's llm_payload verbatim: its `system` prompt untouched,
    /// its `user` text and the horizon-filtered `facts`. Nothing is added —
    /// the excluded sources stay excluded by design.
    static func narrative(for payload: BriefLlmPayload) async throws -> String {
        guard let system = payload.system, !system.isEmpty,
              let user = payload.user else {
            throw NarrativeError.notConfigured
        }

        let envelope: API.NarrativeEnvelope
        do {
            envelope = try await API.narrative(system: system, user: user,
                                               facts: payload.facts)
        } catch let APIError.http(code, _) {
            throw NarrativeError.http(code)
        }

        let text = envelope.narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NarrativeError.emptyResponse }
        return text
    }
}
