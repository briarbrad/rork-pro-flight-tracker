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
/// narrative via the Rork AI proxy. This is an enhancement layer only —
/// the deterministic verdict renders with or without it.
nonisolated enum NarrativeService {
    /// Fast mid-tier model: constrained synthesis over precomputed numbers,
    /// no math or reasoning required. Optimized for latency and cost.
    private static let model = "anthropic/claude-haiku-4.5"

    private nonisolated struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private nonisolated struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    private nonisolated struct ChatResponse: Codable {
        nonisolated struct Choice: Codable {
            nonisolated struct Message: Codable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// Sends the backend's llm_payload verbatim: its `system` prompt untouched,
    /// its `user` text plus the pretty-printed filtered `facts`. Nothing is
    /// added — the excluded sources stay excluded by design.
    static func narrative(for payload: BriefLlmPayload) async throws -> String {
        guard let system = payload.system, !system.isEmpty,
              let user = payload.user else {
            throw NarrativeError.notConfigured
        }
        let base = Config.EXPO_PUBLIC_TOOLKIT_URL
        guard !base.isEmpty,
              let url = URL(string: "\(base)/v2/vercel/v1/chat/completions") else {
            throw NarrativeError.notConfigured
        }

        var userContent = user
        if let facts = payload.facts {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(facts),
               let json = String(data: data, encoding: .utf8) {
                userContent += "\n" + json
            }
        }

        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: userContent),
            ],
            temperature: 0.3,
            maxTokens: 500)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY)",
                         forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NarrativeError.http(0)
        }
        guard http.statusCode == 200 else {
            throw NarrativeError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let text = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw NarrativeError.emptyResponse }
        return text
    }
}
