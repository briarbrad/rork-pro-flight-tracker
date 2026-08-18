import SwiftUI

/// First-open placeholder for the flight screen, shaped like the real
/// layout (hero card, times grid, section cards) with a gentle shimmer —
/// never a blank screen or a lone spinner. The global refresh banner (with
/// its retry) still renders above this if the first pull fails.
struct FlightDetailSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            heroSkeleton
            timesSkeleton
            sectionSkeleton(lines: 3)
            sectionSkeleton(lines: 2)
        }
        .accessibilityLabel("Loading flight data")
    }

    private var heroSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SkeletonBlock(width: 110, height: 22)
                Spacer()
                SkeletonBlock(width: 76, height: 24, radius: 12)
            }
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 64, height: 30)
                    SkeletonBlock(width: 48, height: 14)
                }
                Spacer()
                SkeletonBlock(width: 24, height: 24, radius: 12)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    SkeletonBlock(width: 64, height: 30)
                    SkeletonBlock(width: 48, height: 14)
                }
            }
            SkeletonBlock(width: nil, height: 42, radius: Theme.Radius.well)
        }
        .cardStyle()
    }

    private var timesSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: 140, height: 16)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(width: nil, height: 58, radius: Theme.Radius.well)
                }
            }
        }
        .cardStyle()
    }

    private func sectionSkeleton(lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 160, height: 16)
            ForEach(0..<lines, id: \.self) { _ in
                SkeletonBlock(width: nil, height: 13)
            }
        }
        .cardStyle()
    }
}

/// One shimmering placeholder bar. `width: nil` stretches to fill.
private struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    var radius: CGFloat = 6

    @State private var pulsing: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Theme.hairline.opacity(pulsing ? 0.45 : 0.9))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
