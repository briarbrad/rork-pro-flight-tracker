import Foundation
import UserNotifications

/// Local-notification bridge for the alert engine: the same FlightAlerts that
/// land in the Alerts tab also reach a closed-in-pocket phone. Client-only —
/// no push infrastructure; notifications post when the engine runs.
enum NotificationService {
    /// Asks for notification permission the first time it matters — when a
    /// flight is actually added to the watchlist, never at app launch. A
    /// no-op once the user has answered either way.
    static func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    /// Posts one local notification per newly created alert, grouped per
    /// flight via the thread identifier. Severity maps to interruption level:
    /// WATCH/ACTION break through as time-sensitive; INFO posts passively
    /// (drawer only, no buzz); eased/improved transitions never notify —
    /// good news can wait until the user looks.
    static func post(_ alert: FlightAlert) {
        guard !alert.isImprovement else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            let status = settings.authorizationStatus
            guard status == .authorized || status == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.message
            content.threadIdentifier = alert.ident
            switch alert.level {
            case .high, .moderate:
                content.interruptionLevel = .timeSensitive
                content.sound = .default
            case .low:
                content.interruptionLevel = .passive
            }

            let request = UNNotificationRequest(
                identifier: alert.id.uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
