import Foundation
import Observation

/// Errors from the /api/chat endpoint, mirroring NarrativeError's shape so
/// the two AI surfaces speak with one voice. 501 = the server has no AI
/// provider configured; everything else keeps its status code.
nonisolated enum ChatError: LocalizedError {
    case notConfigured
    case emptyResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI chat is currently unavailable."
        case .emptyResponse:
            return "The answer came back empty — try asking again."
        case .http(let code):
            switch code {
            case 400: return "That question couldn't be sent. Try rephrasing it."
            case 429: return "Too many requests — try again in a moment."
            case 502: return "The AI service didn't answer. Try again in a moment."
            default: return "Chat service error (\(code))."
            }
        }
    }
}

/// One flight's Q&A conversation. The server is stateless — the full turn
/// list ships with every request — so this model owns the history and writes
/// it back into the flight's snapshot (which already persists) after every
/// change. Grounding facts come from the same brief llm_payload the
/// narrative uses; the device never talks to an AI provider directly.
@Observable
final class FlightChatViewModel {
    private let flight: TrackedFlight
    private let store: AppStore

    var messages: [ChatTurn]
    var isSending: Bool = false
    var errorMessage: String?

    init(flight: TrackedFlight, store: AppStore) {
        self.flight = flight
        self.store = store
        self.messages = store.snapshots[flight.id]?.chatHistory ?? []
    }

    /// A failed turn leaves the user's question in place as the last message,
    /// so it can be resent verbatim.
    var canRetry: Bool { messages.last?.isUser == true }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        messages.append(ChatTurn(role: "user", content: trimmed))
        persistHistory()
        await deliver()
    }

    /// Resends the conversation as-is — the last user question is already in
    /// `messages`, so no new turn is appended.
    func retry() async {
        guard canRetry, !isSending else { return }
        await deliver()
    }

    private func deliver() async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let facts = store.snapshots[flight.id]?.brief?.llmPayload?.facts
            let envelope = try await API.chat(flight: flight.ident,
                                              date: flight.date,
                                              facts: facts,
                                              turns: messages)
            let reply = envelope.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else { throw ChatError.emptyResponse }
            messages.append(ChatTurn(role: "assistant", content: reply))
            persistHistory()
        } catch let APIError.http(code, _) {
            let mapped: ChatError = code == 501 ? .notConfigured : .http(code)
            errorMessage = mapped.errorDescription
        } catch let error as ChatError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the conversation into the flight's snapshot and saves — chat
    /// history survives relaunch/kill through the existing snapshot store.
    private func persistHistory() {
        store.repository.snapshots[flight.id]?.chatHistory = messages
        store.repository.saveSnapshot(for: flight.id)
    }
}
