import SwiftUI

/// Free-form Q&A sheet about one flight, grounded in the brief's facts via
/// the app's own backend (/api/chat). History persists per flight in its
/// snapshot, so dismissing never clears the conversation.
struct ChatSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: FlightChatViewModel
    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    private let ident: String

    init(flight: TrackedFlight, store: AppStore) {
        ident = flight.ident
        _viewModel = State(initialValue: FlightChatViewModel(flight: flight, store: store))
    }

    var body: some View {
        NavigationStack {
            conversation
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .background(Theme.canvas)
                .navigationTitle("Ask about \(ident)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .font(TypeScale.bodyStrong)
                            .foregroundStyle(Theme.teal)
                    }
                }
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.sm) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    }
                    ForEach(viewModel.messages) { turn in
                        ChatBubble(turn: turn)
                            .id(turn.id)
                    }
                    if viewModel.isSending {
                        thinkingRow.id("thinking")
                    }
                }
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.md)
            }
            .defaultScrollAnchor(viewModel.messages.isEmpty ? .top : .bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToLatest(proxy)
            }
            .onChange(of: viewModel.isSending) { _, sending in
                if sending {
                    withAnimation(.snappy) { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation(.snappy) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private var emptyState: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.teal)
            Text("Ask anything about this flight")
                .font(TypeScale.titleQuiet)
                .foregroundStyle(Theme.ink)
            Text("Answers are grounded in the same brief facts shown on the flight page — try \u{201C}Why is there a weather delay when the skies are clear?\u{201D}")
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xl)
        .padding(.horizontal, Space.lg)
    }

    /// Left-aligned placeholder bubble while the reply is in flight.
    private var thinkingRow: some View {
        HStack {
            HStack(spacing: Space.xs) {
                ProgressView().controlSize(.small).tint(Theme.teal)
                Text("Thinking…")
                    .font(TypeScale.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs + 2)
            .background(Theme.card)
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            Spacer(minLength: Space.xl + Space.md)
        }
    }

    // MARK: - Composer (error banner + input bar)

    private var composer: some View {
        VStack(spacing: 0) {
            if let message = viewModel.errorMessage {
                errorBanner(message)
            }
            inputBar
        }
        .background(.regularMaterial)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.goldText)
            Text(message)
                .font(TypeScale.caption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.xs)
            if viewModel.canRetry {
                Button {
                    Haptics.tap()
                    Task { await viewModel.retry() }
                } label: {
                    Text("Retry")
                        .font(TypeScale.captionStrong)
                        .foregroundStyle(Theme.teal)
                }
                .disabled(viewModel.isSending)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.staleSurface)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSending
    }

    private var inputBar: some View {
        HStack(spacing: Space.xs) {
            TextField("Ask about this flight…", text: $draft)
                .font(TypeScale.body)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { sendDraft() }
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs + 2)
                .background(Theme.card)
                .clipShape(.rect(cornerRadius: Theme.Radius.well))

            if viewModel.isSending {
                ProgressView().controlSize(.small).tint(Theme.teal)
            }

            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.teal : Theme.inkSecondary.opacity(0.4))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs + 2)
    }

    private func sendDraft() {
        let text = draft
        guard canSend else { return }
        Haptics.tap()
        draft = ""
        Task { await viewModel.send(text) }
    }
}

/// One message bubble: user turns right-aligned in the teal accent, assistant
/// replies left-aligned on a neutral card surface.
private struct ChatBubble: View {
    let turn: ChatTurn

    var body: some View {
        HStack {
            if turn.isUser { Spacer(minLength: Space.xl + Space.md) }
            Text(turn.content)
                .font(TypeScale.body)
                .foregroundStyle(turn.isUser ? .white : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs + 2)
                .background(turn.isUser ? Theme.teal : Theme.card)
                .clipShape(.rect(cornerRadius: Theme.Radius.card))
            if !turn.isUser { Spacer(minLength: Space.xl + Space.md) }
        }
    }
}
