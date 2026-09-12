import Foundation

/// Master presentation mode. Same snapshots and refresh pipeline; only the
/// UI changes. Missing UserDefaults key = Pro, so existing users keep the
/// current full brief / evidence / ATC UI.
nonisolated enum AppDisplayMode: String, Codable, CaseIterable, Sendable {
    case pro
    case simple

    /// Scalar preference — same UserDefaults pattern as `pft.pushToken.v1`.
    static let defaultsKey = "pft.displayMode.v1"

    var title: String {
        switch self {
        case .pro: return "Pro"
        case .simple: return "Simple"
        }
    }

    var subtitle: String {
        switch self {
        case .pro:
            return "Full brief, evidence, ATC flow, and analyst tools."
        case .simple:
            return "Prediction-first tracker. Same data, quieter screen."
        }
    }

    /// Missing or unknown values resolve to Pro — never surprise an existing
    /// user with a stripped layout.
    static func load(from defaults: UserDefaults = .standard) -> AppDisplayMode {
        guard let raw = defaults.string(forKey: defaultsKey), !raw.isEmpty else {
            return .pro
        }
        return AppDisplayMode(rawValue: raw) ?? .pro
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
