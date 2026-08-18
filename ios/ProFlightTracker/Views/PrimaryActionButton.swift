import SwiftUI

/// The app's main call-to-action: full-width teal fill, white semibold
/// label, well-radius corners, built-in haptic tap. Disabled state greys
/// the fill without changing shape.
struct PrimaryActionButton: View {
    let title: String
    var icon: String? = nil
    var iconFallback: String = "circle"
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Space.xs - 2) {
                if let icon {
                    LucideIcon(name: icon, size: 14, fallback: iconFallback)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(isDisabled ? Theme.inkSecondary.opacity(0.5) : Theme.teal)
            .clipShape(.rect(cornerRadius: Theme.Radius.well))
        }
        .disabled(isDisabled)
    }
}
