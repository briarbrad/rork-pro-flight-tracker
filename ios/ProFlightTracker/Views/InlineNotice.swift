import SwiftUI

/// Inline banner for warnings, errors, and informational notes inside a
/// card: severity-tinted icon + caption on a matching soft-fill well, with
/// an optional trailing text action (e.g. Retry). Borderless button style so
/// the action never hijacks an enclosing NavigationLink row.
struct InlineNotice: View {
    enum Style {
        case info, warning, error

        var color: Color {
            switch self {
            case .info: return Theme.teal
            case .warning: return Theme.goldText
            case .error: return Theme.red
            }
        }

        var icon: (name: String, fallback: String) {
            switch self {
            case .info: return ("info", "info.circle")
            case .warning: return ("triangle-alert", "exclamationmark.triangle")
            case .error: return ("circle-alert", "exclamationmark.circle")
            }
        }
    }

    let style: Style
    let message: String
    var actionLabel: String? = nil
    var actionDisabled: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            LucideIcon(name: style.icon.name, size: 13, fallback: style.icon.fallback)
                .padding(.top, 1)
            Text(message)
                .font(TypeScale.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            if let actionLabel, let action {
                Button(actionLabel) {
                    Haptics.tap()
                    action()
                }
                .font(TypeScale.captionStrong)
                .buttonStyle(.borderless)
                .disabled(actionDisabled)
            }
        }
        .foregroundStyle(style.color)
        .padding(Space.sm - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.color.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.Radius.well))
    }
}
