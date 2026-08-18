import SwiftUI

/// The single offline/refresh-failure banner for a screen. Every card keeps
/// rendering its last known data with its own freshness caption; this banner
/// is the ONE place a failed refresh is reported.
struct GlobalRefreshBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(name: "wifi-off", size: 16, fallback: "wifi.slash")
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't refresh")
                    .font(TypeScale.captionBold)
                Text("\(message) Cards below show the last data received.")
                    .font(TypeScale.caption2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let onRetry {
                Button {
                    Haptics.tap()
                    onRetry()
                } label: {
                    Text("Retry")
                        .font(TypeScale.captionBold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.red.opacity(0.12))
                        .clipShape(.capsule)
                }
            }
        }
        .foregroundStyle(Theme.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.Radius.well))
    }
}
