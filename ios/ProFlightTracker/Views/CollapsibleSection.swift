import SwiftUI

/// Disclosure header for sections that are out of phase with the flight's
/// current state (long-horizon reference data day-of, live detail pre-flight).
/// Collapsed it's a slim card row; expanded, the wrapped section cards render
/// beneath it. Nothing loads until expansion beyond what the section itself
/// already holds.
struct CollapsibleSection<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    LucideIcon(name: icon, size: 16, fallback: "circle")
                        .foregroundStyle(Theme.teal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        if let subtitle, !isExpanded {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    LucideIcon(name: isExpanded ? "chevron-up" : "chevron-down",
                               size: 15, fallback: "chevron.down")
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .cardStyle(padding: 14)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
