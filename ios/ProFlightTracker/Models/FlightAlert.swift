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
    var isRead: Bool

    init(flightKey: String, ident: String, title: String, message: String,
         level: RiskLevel, icon: String) {
        self.id = UUID()
        self.flightKey = flightKey
        self.ident = ident
        self.title = title
        self.message = message
        self.level = level
        self.icon = icon
        self.createdAt = Date()
        self.isRead = false
    }
}
