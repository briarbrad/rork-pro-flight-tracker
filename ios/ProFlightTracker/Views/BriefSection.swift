import SwiftUI

/// User-initiated pre-flight brief: one tap calls /api/brief, renders the
/// deterministic verdict immediately, then streams in an AI-written narrative
/// as a pure enhancement. Never polled — the endpoint costs paid flight-data
/// queries, so it only fires on an explicit user action.
///
/// The verdict persists in the store: it is the ONLY flight-level verdict in
/// the app, and its excluded sources also mute matching live signals/alerts.
struct BriefSection: View {
    @Environment(AppStore.self) private var store
    let flight: TrackedFlight

    @State private var runError: String?
    @State private var showExcluded: Bool = false

    private var brief: StoredBrief? { store.snapshots[flight.id]?.brief }
    /// The server-computed live layer from the main refresh — read here only
    /// to gate the horizon row on the FRESHEST phase.
    private var live: StoredLive? { store.snapshots[flight.id]?.live }
    private var isRunning: Bool { store.briefing.contains(flight.id) }
    private var narrativeWriting: Bool { store.narrativePending.contains(flight.id) }
    /// The freshest phase code on file — live layer first, brief fallback.
    private var activePhaseCode: String? { live?.phase?.code ?? brief?.phase?.code }

    var body: some View {
        // Phase, predicted times, and the EDCT banner are owned by the
        // phase-adaptive flight screen — this section is ONLY the brief
        // verdict card (and the run-brief affordance before one exists).
        if let brief {
            verdictCard(brief)
        } else {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader(icon: "radar", title: "Pre-flight brief")
                if isRunning {
                    runningRow
                } else {
                    idleContent
                }
                if let runError {
                    errorRow(runError)
                }
            }
            .cardStyle()
        }
    }

    private func verdictCard(_ brief: StoredBrief) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                SectionHeader(icon: "radar", title: "Pre-flight brief")
                Button {
                    Haptics.tap()
                    Task { await runBrief() }
                } label: {
                    HStack(spacing: 4) {
                        LucideIcon(name: "refresh-cw", size: 11, fallback: "arrow.clockwise")
                        Text("Re-run")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Theme.teal)
                }
                .disabled(isRunning)
            }

            if isRunning {
                runningRow
            } else {
                verdictContent(brief)
            }

            if let runError {
                errorRow(runError)
            }
        }
        .cardStyle()
    }

    // MARK: - Idle / loading

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get a judgement, not just data: the engine works out how far off departure is, consults only the sources that still carry signal at that horizon, and returns a verdict.")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryActionButton(title: "Run brief", icon: "radar", iconFallback: "scope") {
                Task { await runBrief() }
            }
            Text("Uses 2–4 paid flight-data queries, so it only runs when you ask.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var runningRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Theme.teal)
            Text("Assessing \(flight.ident)…")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func errorRow(_ message: String) -> some View {
        InlineNotice(style: .error,
                     message: message,
                     actionLabel: "Retry",
                     actionDisabled: isRunning) {
            Task { await runBrief() }
        }
    }

    // MARK: - Verdict (deterministic, rendered directly from the brief)

    @ViewBuilder
    private func verdictContent(_ brief: StoredBrief) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            verdictHeader(brief)

            horizonRow(brief)

            if let basis = brief.confidenceBasis, brief.isNeutral {
                Text(basis)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if brief.hasEffects {
                // Effects[] is the primary explanation — severities computed
                // server-side (direction-aware), rendered as-is.
                EffectsList(effects: brief.orderedEffects)
            } else {
                // Older briefs without effects fall back to drivers/branch.
                if !brief.drivers.isEmpty {
                    driversBlock(brief.drivers)
                }
                if !brief.isTooEarly, let label = brief.branchLabel {
                    branchBlock(brief, label: label)
                }
            }

            if !brief.sourcesExcluded.isEmpty {
                excludedBlock(brief.sourcesExcluded)
            }

            // One freshness language: "Brief run Xm ago", amber with the
            // re-run affordance once the server staleness threshold passes.
            // Never a polling trigger — the brief stays user-initiated.
            FreshnessCaption(asOf: brief.runAt,
                             prefix: "Brief run",
                             isStale: brief.isStale,
                             staleHint: "the flight has moved on. Re-run for the live picture.") {
                Task { await runBrief() }
            }
        }
        // A stale brief greys out — it described the flight as of run time.
        .opacity(brief.isStale ? 0.75 : 1)
    }

    private func verdictHeader(_ brief: StoredBrief) -> some View {
        // LOW risk at LOW confidence is NOT "this flight is fine" — it's
        // "nothing visibly wrong yet, too early to tell." Those states must
        // not share the reassuring green treatment.
        let neutral = brief.isNeutral
        let badgeTone: ChipTone = neutral ? .neutral : (brief.riskLevel.map(ChipTone.from) ?? .neutral)
        let badgeIcon: String = neutral ? "hourglass" : (brief.riskLevel?.lucideIcon ?? "shield-question-mark")
        let badgeText: String = {
            if brief.isTooEarly { return "Too early to assess" }
            if neutral { return "Nothing visible yet" }
            return brief.riskLevel?.label ?? (brief.risk ?? "Unknown")
        }()

        return HStack(spacing: 10) {
            StatusChip(text: badgeText, icon: badgeIcon, tone: badgeTone)

            Spacer()

            if let confidence = brief.confidence {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Confidence")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(confidence.capitalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(confidenceColor(confidence))
                }
            }
        }
    }

    @ViewBuilder
    private func horizonRow(_ brief: StoredBrief) -> some View {
        // Post-pushback the phase card is the state — a horizon row saying
        // "departed" next to a live taxi hold is exactly the hole this fixes.
        // Gated on the FRESHEST phase (live layer first), not just the brief's.
        if let code = activePhaseCode, code != "PRE_GATE" {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                LucideIcon(name: "clock", size: 12, fallback: "clock")
                    .foregroundStyle(Theme.teal)
                if let departsIn = departsInText(brief) {
                    Text("Departs \(departsIn)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                if let band = brief.band {
                    StatusChip(text: bandLabel(band), tone: .info, size: .mini)
                }
                Spacer()
            }
        }
    }

    private func driversBlock(_ drivers: [String]) -> some View {
        InsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's driving this")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                ForEach(Array(drivers.enumerated()), id: \.offset) { _, driver in
                    HStack(alignment: .top, spacing: Space.xs) {
                        Circle()
                            .fill(Theme.teal)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        GlossaryText(text: driver, font: .caption, color: Theme.inkSecondary)
                    }
                }
            }
        }
    }

    private func branchBlock(_ brief: StoredBrief, label: String) -> some View {
        InsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    LucideIcon(name: "git-branch", size: 12, fallback: "arrow.triangle.branch")
                        .foregroundStyle(Theme.teal)
                    Text("Delay mechanism")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    if let code = brief.branch, code.uppercased() != "UNDETERMINED" {
                        StatusChip(text: code, tone: .info, size: .mini, uppercased: true)
                    }
                }
                GlossaryText(text: label, font: .caption, color: Theme.inkSecondary)
                ForEach(Array(brief.branchEvidence.prefix(3).enumerated()), id: \.offset) { _, item in
                    GlossaryText(text: item, font: .caption2, color: Theme.inkSecondary)
                }
            }
        }
    }

    private func excludedBlock(_ excluded: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { showExcluded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(name: "eye-off", size: 12, fallback: "eye.slash")
                    Text("Deliberately not checked at this horizon (\(excluded.count))")
                        .font(.caption2.weight(.semibold))
                    LucideIcon(name: showExcluded ? "chevron-up" : "chevron-down",
                               size: 11, fallback: "chevron.down")
                }
                .foregroundStyle(Theme.inkSecondary)
            }
            if showExcluded {
                ForEach(excluded.sorted(by: { $0.key < $1.key }), id: \.key) { key, reason in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sourceName(key))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("These are also filtered out of this flight's live signals and alerts until they carry signal again.")
                    .font(.caption2.italic())
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func runBrief() async {
        runError = nil
        do {
            try await store.runBrief(for: flight)
            Haptics.success()
        } catch {
            runError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Pre-departure countdown only. Negative hours after pushback are
    /// correct (not an error) — but once a phase exists, the PhaseCard owns
    /// the post-pushback story and "departed" here would repeat the old bug
    /// of calling a taxi hold finished.
    private func departsInText(_ brief: StoredBrief) -> String? {
        guard let hours = brief.hoursToDepartureNow else { return nil }
        if hours < 0 {
            return brief.phase == nil ? "— departed" : nil
        }
        if hours < 2 { return "in \(Int((hours * 60).rounded())) min" }
        return "in ~\(Int(hours.rounded()))h"
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence.uppercased() {
        case "HIGH": return Theme.greenText
        case "MEDIUM": return Theme.teal
        default: return Theme.inkSecondary
        }
    }

    private func bandLabel(_ band: String) -> String {
        switch band.uppercased() {
        case "IMMINENT": return "Imminent · 0–2h"
        case "NEAR": return "Near · 2–6h"
        case "SAME_DAY": return "Same day · 6–12h"
        case "NEXT_DAY": return "Next day · 12–24h"
        case "DISTANT": return "Distant · 24h+"
        default: return band
        }
    }

    private func sourceName(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Analyst narrative, demoted to a collapsed section at the bottom of the
/// flight screen. With effects and predictions rendered natively, the prose
/// is color commentary — never the main event, and the verdict never waits
/// on it.
struct NarrativeSection: View {
    @Environment(AppStore.self) private var store
    let flight: TrackedFlight

    @State private var isExpanded: Bool = false

    private var brief: StoredBrief? { store.snapshots[flight.id]?.brief }
    private var isWriting: Bool { store.narrativePending.contains(flight.id) }

    var body: some View {
        if let brief, brief.narrative != nil || isWriting || brief.narrativeFailed {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        LucideIcon(name: "sparkles", size: 14, fallback: "sparkles")
                            .foregroundStyle(Theme.gold)
                        Text("Analyst narrative")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if isWriting {
                            ProgressView().controlSize(.mini).tint(Theme.inkSecondary)
                        } else {
                            LucideIcon(name: isExpanded ? "chevron-up" : "chevron-down",
                                       size: 13, fallback: "chevron.down")
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    if let narrative = brief.narrative {
                        GlossaryText(text: narrative, font: .subheadline, color: Theme.ink)
                    } else if isWriting {
                        Text("Writing narrative…")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    } else {
                        Text("Narrative unavailable — the predictions and effects above are the full deterministic assessment.")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            .cardStyle()
        }
    }
}
