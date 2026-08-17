import Foundation

/// One timestamped early-warning alert shown in the Alerts tab.
nonisolated struct FlightAlert: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let flightKey: String
    let ident: String
    let title: String
    let message: String
    let level: RiskLevel
    let icon: String
    let createdAt: Date
    /// True for "eased/improved" transitions — good news stays in the drawer:
    /// it never buzzes the pocket and never counts toward the tab badge.
    let isImprovement: Bool
    var isRead: Bool

    init(flightKey: String, ident: String, title: String, message: String,
         level: RiskLevel, icon: String, isImprovement: Bool = false) {
        self.id = UUID()
        self.flightKey = flightKey
        self.ident = ident
        self.title = title
        self.message = message
        self.level = level
        self.icon = icon
        self.createdAt = Date()
        self.isImprovement = isImprovement
        self.isRead = false
    }

    /// Optional-safe decoding so alerts persisted before `isImprovement`
    /// existed still load (they were all deteriorations or signal fires).
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
        isImprovement = try container.decodeIfPresent(Bool.self, forKey: .isImprovement) ?? false
        isRead = try container.decode(Bool.self, forKey: .isRead)
    }
}
