import SwiftUI

/// Soft-slate design system: warm light canvas, white cards, deep teal accent,
/// gold caution, red danger. Matches the risk color convention of the backend.
enum Theme {
    static let canvas = Color(red: 0.957, green: 0.949, blue: 0.933)
    static let card = Color.white
    static let teal = Color(red: 0.086, green: 0.412, blue: 0.478)
    static let tealDeep = Color(red: 0.055, green: 0.298, blue: 0.345)
    static let gold = Color(red: 0.918, green: 0.639, blue: 0.043)
    static let red = Color(red: 0.804, green: 0.235, blue: 0.2)
    static let green = Color(red: 0.165, green: 0.573, blue: 0.396)
    static let ink = Color(red: 0.122, green: 0.161, blue: 0.2)
    static let inkSecondary = Color(red: 0.373, green: 0.42, blue: 0.463)
    static let hairline = Color(red: 0.882, green: 0.871, blue: 0.843)
}

/// Reusable card container with soft shadow and rounded corners.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(.rect(cornerRadius: 18))
            .shadow(color: Theme.ink.opacity(0.05), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// Light haptic tap used across cards and buttons.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
