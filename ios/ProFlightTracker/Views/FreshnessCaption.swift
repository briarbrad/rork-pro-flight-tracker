import SwiftUI

/// The ONE freshness language across the app: a small "as of Xm ago" caption
/// anchored to the SOURCE timestamp of the data behind a card (never HTTP
/// receipt time). Once the data is older than its refresh window the caption
/// turns amber; when an action is provided, the amber state becomes the
/// user-initiated refresh affordance (never a poll — refreshes cost paid
/// queries).
struct FreshnessCaption: View {
    let asOf: Date
    var prefix: String = "as of"
    var isStale: Bool = false
    /// Appended to the amber state, e.g. "refresh for the current picture."
    var staleHint: String? = nil
    var onAction: (() -> Void)? = nil

    private var ageText: String {
        Date().timeIntervalSince(asOf) < 60 ? "just now" : TimeFmt.relative(asOf)
    }

    var body: some View {
        if isStale, onAction != nil {
            staleWell
        } else {
            HStack(spacing: 4) {
                LucideIcon(name: "history", size: 10, fallback: "clock")
                Text("\(prefix) \(ageText)")
                    .monospacedDigit()
            }
            .font(TypeScale.caption2)
            .foregroundStyle(isStale ? Theme.goldText : Theme.inkSecondary)
        }
    }

    /// Amber refresh affordance for stale data — always user-initiated.
    private var staleWell: some View {
        Button {
            Haptics.tap()
            onAction?()
        } label: {
            HStack(spacing: 6) {
                LucideIcon(name: "history", size: 11, fallback: "clock")
                    .foregroundStyle(Theme.gold)
                Text(staleText)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(TypeScale.caption2Strong)
            .foregroundStyle(Theme.goldText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.gold.opacity(0.1))
            .clipShape(.rect(cornerRadius: Theme.Radius.well))
        }
    }

    private var staleText: String {
        let lead = "\(prefix.prefix(1).uppercased() + prefix.dropFirst()) \(ageText)"
        guard let staleHint, !staleHint.isEmpty else { return lead }
        return "\(lead) — \(staleHint)"
    }
}
