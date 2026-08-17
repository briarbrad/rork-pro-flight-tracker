import SwiftUI

/// Centered floating detail card over a dimmed backdrop. Presented inside a
/// `.fullScreenCover` with a clear presentation background; springs in,
/// dismisses on swipe-down, backdrop tap, or the close button.
struct FloatingCardCover<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    @State private var shown: Bool = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.42 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            card
                .padding(.horizontal, 20)
                .scaleEffect(shown ? 1 : 0.88)
                .opacity(shown ? 1 : 0)
                .offset(y: dragOffset)
        }
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                shown = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.hairline)
                .frame(width: 38, height: 5)
                .padding(.top, 9)
                .padding(.bottom, 3)

            header

            Divider().overlay(Theme.hairline)

            ScrollView {
                content()
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 460)
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.modal))
        .shadow(color: .black.opacity(0.22), radius: 26, y: 10)
        .gesture(dragGesture)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)
                LucideIcon(name: icon, size: 16, fallback: "info.circle")
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
            Button {
                close()
            } label: {
                LucideIcon(name: "x", size: 14, fallback: "xmark")
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(9)
                    .background(Theme.canvas)
                    .clipShape(.circle)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = max(0, value.translation.height) * 0.85
            }
            .onEnded { value in
                if value.translation.height > 110 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func close() {
        Haptics.tap()
        withAnimation(.easeIn(duration: 0.15)) {
            shown = false
            dragOffset += 30
        }
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            dismiss()
        }
    }
}
