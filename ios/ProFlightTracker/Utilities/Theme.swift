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
    /// Darkened companions that pass WCAG AA on white — gold (#EAA30B) is
    /// ~2.15:1 and green ~3.9:1, both illegible at chip sizes. Use these for
    /// TEXT in chips/badges/banners; keep the bright hues for fills and icons.
    static let goldText = Color(red: 0.541, green: 0.38, blue: 0.0)
    static let greenText = Color(red: 0.118, green: 0.439, blue: 0.314)

    /// Text-safe variant of an accent: gold and green darken to their
    /// AA-passing companions, every other color passes through unchanged.
    static func textVariant(of color: Color) -> Color {
        if color == gold { return goldText }
        if color == green { return greenText }
        return color
    }
    /// Muted card surface for stale data — a warm tint that reads as "not
    /// current" WITHOUT dimming text. Never fade content to signal staleness.
    static let staleSurface = Color(red: 0.988, green: 0.969, blue: 0.925)
    static let ink = Color(red: 0.122, green: 0.161, blue: 0.2)
    static let inkSecondary = Color(red: 0.373, green: 0.42, blue: 0.463)
    static let hairline = Color(red: 0.882, green: 0.871, blue: 0.843)

    /// Canonical corner radii: inner wells 12, cards 16, modals 24.
    enum Radius {
        static let well: CGFloat = 12
        static let card: CGFloat = 16
        static let modal: CGFloat = 24
    }
}

/// Reusable card container with soft shadow and rounded corners.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .cardShadow()
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// The one card shadow used across the app.
    func cardShadow() -> some View {
        shadow(color: Theme.ink.opacity(0.05), radius: 8, x: 0, y: 3)
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
