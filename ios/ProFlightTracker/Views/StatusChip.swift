import SwiftUI

/// Semantic tone of a chip — mapped centrally to color so severity always
/// reads the same everywhere: ok=green, watch=gold, alert=red, info=teal,
/// neutral=secondary ink. Text uses the AA-safe darkened companions.
enum ChipTone {
    case ok, watch, alert, info, neutral

    /// Bright hue — for fills and icons.
    var color: Color {
        switch self {
        case .ok: return Theme.green
        case .watch: return Theme.gold
        case .alert: return Theme.red
        case .info: return Theme.teal
        case .neutral: return Theme.inkSecondary
        }
    }

    /// AA-passing companion for text at chip sizes.
    var textColor: Color { Theme.textVariant(of: color) }

    static func from(_ level: RiskLevel) -> ChipTone {
        switch level {
        case .low: return .ok
        case .moderate: return .watch
        case .high: return .alert
        }
    }
}

/// The app's single chip/pill primitive. Every status, tag, and delta chip
/// renders through this so metrics and severity colors never drift.
///
/// - `.tinted` (default): tone fill at 0.12 opacity, AA tone text.
/// - `.solid`: deep-teal fill with white text — reserved EXCLUSIVELY for
///   FAA-authoritative facts (the EDCT slot). Estimates never wear it.
struct StatusChip: View {
    let text: String
    var icon: String? = nil
    var tone: ChipTone = .neutral
    var size: Size = .regular
    var style: Style = .tinted
    /// Uppercase-tag treatment (adds tracking) for label-style chips.
    var uppercased: Bool = false
    /// Trailing affordance (e.g. chevron) for chips that open a popup.
    var trailingIcon: String? = nil

    enum Size { case regular, mini }
    enum Style { case tinted, solid }

    var body: some View {
        HStack(spacing: size == .regular ? 5 : 4) {
            if let icon {
                LucideIcon(name: icon, size: size == .regular ? 12 : 11,
                           fallback: "circle")
                    .foregroundStyle(style == .solid ? .white : tone.color)
            }
            Text(text)
                .font(size == .regular ? .caption.weight(.semibold) : .caption2.weight(.bold))
                .monospacedDigit()
                .textCase(uppercased ? .uppercase : nil)
                .kerning(uppercased ? 0.6 : 0)
                .lineLimit(1)
            if let trailingIcon {
                LucideIcon(name: trailingIcon, size: size == .regular ? 10 : 9,
                           fallback: "chevron.right")
            }
        }
        .foregroundStyle(style == .solid ? .white : tone.textColor)
        .padding(.horizontal, size == .regular ? 10 : 7)
        .padding(.vertical, size == .regular ? 5 : 3)
        .background(style == .solid ? Theme.tealDeep : tone.color.opacity(0.12))
        .clipShape(.capsule)
    }
}
