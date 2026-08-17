import Foundation
import SwiftUI

/// Overall risk level. Mirrors the backend's LOW / MODERATE / HIGH convention.
nonisolated enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case low = "LOW"
    case moderate = "MODERATE"
    case high = "HIGH"

    var rank: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .high: return 2
        }
    }

    var label: String {
        switch self {
        case .low: return "Low risk"
        case .moderate: return "Watch"
        case .high: return "High risk"
        }
    }

    var color: Color {
        switch self {
        case .low: return Theme.green
        case .moderate: return Theme.gold
        case .high: return Theme.red
        }
    }

    var lucideIcon: String {
        switch self {
        case .low: return "shield-check"
        case .moderate: return "triangle-alert"
        case .high: return "octagon-alert"
        }
    }

    static func worse(_ a: RiskLevel, _ b: RiskLevel) -> RiskLevel {
        a.rank >= b.rank ? a : b
    }
}

/// One fired early-warning signal with a stable key for diffing between checks.
nonisolated struct RiskSignal: Codable, Identifiable, Hashable, Sendable {
    let key: String
    let title: String
    let detail: String
    let level: RiskLevel
    let icon: String

    var id: String { key }
}

/// Result of a client-side risk evaluation across all fetched data sources.
nonisolated struct RiskAssessment: Codable, Hashable, Sendable {
    let level: RiskLevel
    let signals: [RiskSignal]
    let evaluatedAt: Date
}
