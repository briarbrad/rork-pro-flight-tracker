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
    /// Origin/destination zones for the client-side fallback when the backend's
    /// own zone lookup comes back empty.
    private var zones: FlightZones {
        FlightZones.resolve(flight: store.snapshots[flight.id]?.flight, brief: brief?.timezones)
    }
    private var isRunning: Bool { store.briefing.contains(flight.id) }
    private var narrativeWriting: Bool { store.narrativePending.contains(flight.id) }

    var body: some View {
        VStack(spacing: 14) {
            if let brief {
                // Phase is the primary state — read before horizon. Once the
                // aircraft is out of the gate (or the flight is over), the
                // screen is organised around "what happens next", not the
                // schedule.
                if let phase = brief.phase, phase.code != "PRE_GATE" {
                    PhaseCard(brief: brief, zones: zones) {
                        Task { await runBrief() }
                    }
                }
                // Headline: server-predicted times — when does this flight GO.
                if let times = brief.predictedTimes {
                    PredictedTimesCard(times: times, timezones: brief.timezones, zones: zones,
                                       isStale: brief.isStale, runAt: brief.runAt) {
                        Task { await runBrief() }
                    }
                }
                // FAA-controlled wheels-up slot: the top fact when present.
                if let edct = brief.predictedTimes?.edct, edct.edct != nil {
                    EdctBanner(edct: edct, originZone: zones.origin)
                }
                verdictCard(brief)
            } else {
                VStack(alignment: .leading, spacing: 12) {
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
    }

    private func verdictCard(_ brief: StoredBrief) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Button {
                Haptics.tap()
                Task { await runBrief() }
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(name: "radar", size: 14, fallback: "scope")
                    Text("Run brief")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Theme.teal)
                .clipShape(.rect(cornerRadius: 12))
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
        HStack(spacing: 8) {
            LucideIcon(name: "circle-alert", size: 13, fallback: "exclamationmark.circle")
            Text(message)
                .font(.caption)
            Spacer()
            Button("Retry") {
                Haptics.tap()
                Task { await runBrief() }
            }
            .font(.caption.weight(.semibold))
            .disabled(isRunning)
        }
        .foregroundStyle(Theme.red)
        .padding(10)
        .background(Theme.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
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

            // Server staleness threshold, not a polling trigger: the brief
            // stays user-initiated, this just says when it stopped describing
            // the flight's current state.
            if brief.isStale {
                Button {
                    Haptics.tap()
                    Task { await runBrief() }
                } label: {
                    HStack(spacing: 6) {
                        LucideIcon(name: "history", size: 11, fallback: "clock")
                            .foregroundStyle(Theme.gold)
                        Text("Brief run \(TimeFmt.relative(brief.runAt)) — the flight has moved on. Re-run for the live picture.")
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.goldText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.gold.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 10))
                }
                .disabled(isRunning)
            } else {
                HStack(spacing: 4) {
                    LucideIcon(name: "history", size: 10, fallback: "clock")
                    Text("Brief run \(TimeFmt.relative(brief.runAt))")
                }
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
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
        let badgeColor: Color = neutral ? Theme.inkSecondary : (brief.riskLevel?.color ?? Theme.inkSecondary)
        let badgeIcon: String = neutral ? "hourglass" : (brief.riskLevel?.lucideIcon ?? "shield-question-mark")
        let badgeText: String = {
            if brief.isTooEarly { return "Too early to assess" }
            if neutral { return "Nothing visible yet" }
            return brief.riskLevel?.label ?? (brief.risk ?? "Unknown")
        }()

        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                LucideIcon(name: badgeIcon, size: 14, fallback: "shield")
                Text(badgeText)
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(badgeColor.opacity(0.12))
            .clipShape(.capsule)

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
        if let phase = brief.phase, phase.code != "PRE_GATE" {
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
                    Text(bandLabel(band))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.teal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.teal.opacity(0.1))
                        .clipShape(.capsule)
                }
                Spacer()
            }
        }
    }

    private func driversBlock(_ drivers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's driving this")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.ink)
            ForEach(Array(drivers.enumerated()), id: \.offset) { _, driver in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Theme.teal)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                    GlossaryText(text: driver, font: .caption, color: Theme.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func branchBlock(_ brief: StoredBrief, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LucideIcon(name: "git-branch", size: 12, fallback: "arrow.triangle.branch")
                    .foregroundStyle(Theme.teal)
                Text("Delay mechanism")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ink)
                if let code = brief.branch, code.uppercased() != "UNDETERMINED" {
                    Text(code)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Theme.teal)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.teal.opacity(0.12))
                        .clipShape(.capsule)
                }
            }
            GlossaryText(text: label, font: .caption, color: Theme.inkSecondary)
            ForEach(Array(brief.branchEvidence.prefix(3).enumerated()), id: \.offset) { _, item in
                GlossaryText(text: item, font: .caption2, color: Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: 12))
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
        case "HIGH": return Theme.green
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
