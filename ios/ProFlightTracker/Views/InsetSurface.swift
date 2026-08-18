import SwiftUI

/// The app's one inner-well container: canvas-tinted surface, `Space.sm`
/// padding, `Theme.Radius.well` corners, full width. Every "block inside a
/// card" (drivers, ops feeds, popup sections, TAF timelines) renders on this
/// instead of hand-rolled padding/background/clipShape chains.
struct InsetSurface<Content: View>: View {
    /// Surface color — defaults to the canvas well; pass a tinted color for
    /// severity-flavored blocks (e.g. `Theme.gold.opacity(0.07)`).
    var tint: Color = Theme.canvas
    var padding: CGFloat = Space.sm
    var alignment: Alignment = .leading
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(padding)
            .background(tint)
            .clipShape(.rect(cornerRadius: Theme.Radius.well))
    }
}
