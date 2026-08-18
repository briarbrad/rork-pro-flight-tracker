import SwiftUI

/// The app's one empty/no-data treatment: tinted icon disc, semibold title,
/// centered secondary message, optional footer content (e.g. a CTA button).
struct EmptyState<Footer: View>: View {
    let icon: String
    var iconFallback: String = "circle"
    var tint: Color = Theme.teal
    let title: String
    let message: String
    @ViewBuilder var footer: Footer

    init(icon: String,
         iconFallback: String = "circle",
         tint: Color = Theme.teal,
         title: String,
         message: String,
         @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.icon = icon
        self.iconFallback = iconFallback
        self.tint = tint
        self.title = title
        self.message = message
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: Space.md - 2) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 96, height: 96)
                LucideIcon(name: icon, size: 42, fallback: iconFallback)
                    .foregroundStyle(tint)
            }
            VStack(spacing: Space.xxs + 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl)
            }
            footer
        }
    }
}
