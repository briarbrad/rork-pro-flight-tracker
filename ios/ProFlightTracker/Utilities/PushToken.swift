import Foundation

/// Server-side tracking (`POST /api/track`) is only useful when the token can
/// actually receive an Expo push. Preview builds persist a stable placeholder
/// so the value does not churn, but that string must never be registered —
/// the backend tracker would spend AeroAPI credit on pushes that fail silently.
nonisolated enum PushToken {
    static let previewPrefix = "rork-ios-preview-"

    /// True when `token` is a real deliverable push credential, not a
    /// preview placeholder or an empty stub.
    static func isDeliverable(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !trimmed.hasPrefix(previewPrefix)
    }
}
