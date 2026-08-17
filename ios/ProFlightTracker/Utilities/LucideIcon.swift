import SwiftUI
import LucideIcons

/// Renders a Lucide icon by its lucide.dev id, tinted via `.foregroundStyle`.
/// Falls back to an SF Symbol when the id is unknown.
struct LucideIcon: View {
    let name: String
    var size: CGFloat = 18
    var fallback: String = "circle"

    var body: some View {
        if let image = UIImage(lucideId: name)?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size * 0.82, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}
