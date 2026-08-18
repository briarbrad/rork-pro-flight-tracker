import SwiftUI

/// Disclosure header for sections that are out of phase with the flight's
/// current state (long-horizon reference data day-of, live detail pre-flight).
/// Header and content share ONE card: collapsed it's a slim row; expanded, the
/// content unfolds beneath a hairline inside the same surface — never a second
/// floating capsule. Wrapped sections should render in their `embedded` form
/// (no own card shell, no repeated title).
struct CollapsibleSection<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    LucideIcon(name: icon, size: 16, fallback: "circle")
                        .foregroundStyle(Theme.teal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(TypeScale.sectionTitle)
                            .foregroundStyle(Theme.ink)
                        if let subtitle, !isExpanded {
                            Text(subtitle)
                                .font(TypeScale.caption2)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    LucideIcon(name: isExpanded ? "chevron-up" : "chevron-down",
                               size: 15, fallback: "chevron.down")
                        .foregroundStyle(Theme.inkSecondary)
                }
                // Full-width hit target for the whole header row.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .overlay(Theme.hairline)
                    .padding(.top, 14)
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.top, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle(padding: 14)
    }
}
