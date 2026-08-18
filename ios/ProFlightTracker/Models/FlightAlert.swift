import Foundation

/// One timestamped early-warning alert shown in the Alerts tab.
/// Alerts are deduplicated by `dedupKey`: when the same underlying event
/// changes (e.g. an EDCT slot moves), the existing alert is updated in place
/// with a fresh `updatedAt` instead of stacking a second entry.
nonisolated struct FlightAlert: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let flightKey: String
    let ident: String
    var title: String
    var message: String
    var level: RiskLevel
    var icon: String
    let createdAt: Date
    /// Bumped whenever the same underlying event re-fires with new details.
    var updatedAt: Date
    /// True for "eased/improved" transitions — good news stays in the drawer:
    /// it never buzzes the pocket and never counts toward the tab badge.
    var isImprovement: Bool
    var isRead: Bool
    /// Correlates alerts about the same underlying event (per flight).
    /// Signals use "signal.<key>", level transitions use "level".
    let dedupKey: String
    /// "SFO → JFK" captured when the alert fired.
    let route: String?
    /// Flight phase at fire time, e.g. "Taxiing out".
    let phaseLabel: String?
    /// Short "what changed" context, e.g. "New — wasn't firing before".
    var changeNote: String?

    init(flightKey: String, ident: String, title: String, message: String,
         level: RiskLevel, icon: String, isImprovement: Bool = false,
         dedupKey: String, route: String? = nil, phaseLabel: String? = nil,
         changeNote: String? = nil) {
        self.id = UUID()
        self.flightKey = flightKey
        self.ident = ident
        self.title = title
        self.message = message
        self.level = level
        self.icon = icon
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isImprovement = isImprovement
        self.isRead = false
        self.dedupKey = dedupKey
        self.route = route
        self.phaseLabel = phaseLabel
        self.changeNote = changeNote
    }

    var wasUpdated: Bool { updatedAt.timeIntervalSince(createdAt) > 60 }

    /// Optional-safe decoding so alerts persisted before the newer fields
    /// existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        flightKey = try container.decode(String.self, forKey: .flightKey)
        ident = try container.decode(String.self, forKey: .ident)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        level = try container.decode(RiskLevel.self, forKey: .level)
        icon = try container.decode(String.self, forKey: .icon)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? createdAt
        isImprovement = try container.decodeIfPresent(Bool.self, forKey: .isImprovement) ?? false
        isRead = try container.decode(Bool.self, forKey: .isRead)
        // Legacy alerts get a unique key so they never merge with new ones.
        dedupKey = try container.decodeIfPresent(String.self, forKey: .dedupKey)
            ?? "legacy.\(id.uuidString)"
        route = try container.decodeIfPresent(String.self, forKey: .route)
        phaseLabel = try container.decodeIfPresent(String.self, forKey: .phaseLabel)
        changeNote = try container.decodeIfPresent(String.self, forKey: .changeNote)
    }
}
