import SwiftUI

/// ATC flow: TFMS/GDP advisories, TBFM meter-fix ETAs, TFDM taxi/queue, and
/// server `effects[]` rendered verbatim. Lazy-loaded like OpsSection — the
/// composed `/api/ops/flow-brief` is free but slow, so it only fires when
/// the traveller expands. Horizon-gated to the same-day window.
///
/// Day-of this is a peer card near the hero/map. Pre-flight it lives inside
/// the evidence drawer (`embedded: true`).
struct FlowSection: View {
    let flightIdent: String
    let date: String
    let originIcao: String?
    let destIcao: String?
    var hoursToDeparture: Double? = nil
    var embedded: Bool = false

    @State private var isExpanded: Bool = false
    @State private var isLoading: Bool = false
    @State private var brief: FlowBriefEnvelope?
    @State private var loadError: String?
    @State private var endpointMissing: Bool = false

    var body: some View {
        if originIcao != nil || destIcao != nil {
            if HorizonGate.sameDaySourcesCarrySignal(hoursToDeparture: hoursToDeparture) {
                if embedded { liveCard } else { liveCard.cardStyle() }
            } else {
                if embedded { lockedCard } else { lockedCard.cardStyle() }
            }
        }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { isExpanded.toggle() }
                if isExpanded, brief == nil, !isLoading {
                    loadFlow()
                }
            } label: {
                HStack(spacing: 8) {
                    LucideIcon(name: "tower-control", size: 16, fallback: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Theme.teal)
                    Text("ATC flow")
                        .font(TypeScale.sectionTitle)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small).tint(Theme.teal)
                    }
                    LucideIcon(name: isExpanded ? "chevron-up" : "chevron-down",
                               size: 15, fallback: "chevron.down")
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)

            if !isExpanded {
                Text("TFMS advisories, TBFM meter times, TFDM taxi queues")
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }

            if isExpanded {
                if let loadError {
                    InlineNotice(style: .error,
                                 message: loadError,
                                 actionLabel: "Retry",
                                 actionDisabled: isLoading) {
                        loadFlow()
                    }
                }
                if isLoading && brief == nil {
                    Text("Listening to FAA flow feeds — TFMS, TBFM, and TFDM can take 10–15 seconds…")
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                if let brief {
                    flowBody(brief)
                } else if !isLoading, loadError == nil, endpointMissing {
                    Text("ATC flow brief isn't on this server yet. Individual SWIM helpers were quiet or unavailable — expand again after the backend ships `/api/ops/flow-brief`.")
                        .font(TypeScale.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LucideIcon(name: "tower-control", size: 16, fallback: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Theme.inkSecondary)
                Text("ATC flow")
                    .font(TypeScale.sectionTitle)
                    .foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 4) {
                    LucideIcon(name: "lock", size: 11, fallback: "lock")
                    Text(unlockText)
                        .font(TypeScale.caption2Strong)
                }
                .foregroundStyle(Theme.inkSecondary)
            }
            Text("TFMS advisories, TBFM meter times, and TFDM taxi queues describe the next few hours — this far out they can't tell you anything about your departure, so the app doesn't pull them yet.")
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unlockText: String {
        guard let hours = hoursToDeparture, hours > HorizonGate.sameDayWindowHours else {
            return "Unlocks closer to departure"
        }
        let remaining = Int((hours - HorizonGate.sameDayWindowHours).rounded())
        return remaining <= 1 ? "Unlocks within the hour" : "Unlocks in ~\(remaining)h"
    }

    // MARK: - Body

    @ViewBuilder
    private func flowBody(_ brief: FlowBriefEnvelope) -> some View {
        if !brief.hasContent {
            Text(brief.composedFromHelpers == true
                 ? "No active TFMS advisories, TBFM meter times, or TFDM queue data in the capture window."
                 : (brief.summary ?? "No active flow programs for this flight right now."))
                .font(TypeScale.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            if !brief.orderedEffects.isEmpty {
                EffectsList(effects: brief.orderedEffects)
            }
            if let advisories = brief.advisories, !advisories.isEmpty {
                advisoriesBlock(advisories)
            }
            if let fixes = brief.meterFixes, !fixes.isEmpty {
                meterBlock(fixes)
            }
            if let tfdm = brief.tfdm, tfdm.hasContent {
                tfdmBlock(tfdm)
            }
            Text("Context only — these are live NAS feeds, not a second verdict. Effects above are the server's, rendered as-is.")
                .font(TypeScale.caption2)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func advisoriesBlock(_ advisories: [FlowAdvisory]) -> some View {
        flowBlock(icon: "megaphone", title: "TFMS / GDP advisories") {
            ForEach(Array(advisories.prefix(5).enumerated()), id: \.offset) { _, advisory in
                VStack(alignment: .leading, spacing: 3) {
                    GlossaryText(text: advisory.displayLine,
                                 font: .caption.weight(.semibold),
                                 color: Theme.ink)
                    HStack(spacing: 6) {
                        if let number = advisory.advisoryNumber, !number.isEmpty {
                            StatusChip(text: number, tone: .info, size: .mini)
                        }
                        if let window = advisory.windowText {
                            Text(window)
                                .font(TypeScale.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if advisories.count > 5 {
                Text("+ \(advisories.count - 5) more")
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func meterBlock(_ fixes: [FlowMeterFix]) -> some View {
        flowBlock(icon: "timer", title: "TBFM meter-fix ETAs") {
            ForEach(Array(fixes.prefix(4).enumerated()), id: \.offset) { _, fix in
                HStack(spacing: 8) {
                    GlossaryText(text: fix.headline,
                                 font: .caption.weight(.semibold),
                                 color: Theme.ink)
                    Spacer(minLength: 0)
                    if let ident = fix.flightId, !ident.isEmpty {
                        Text(ident)
                            .font(TypeScale.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
    }

    private func tfdmBlock(_ tfdm: FlowTfdm) -> some View {
        flowBlock(icon: "milestone", title: tfdm.airport.map { "TFDM surface — \($0)" } ?? "TFDM surface") {
            HStack(spacing: 6) {
                if let queue = tfdm.queueWaitMinutes?.intValue {
                    StatusChip(text: "Queue \(queue) min", tone: queue >= 20 ? .watch : .info, size: .mini)
                }
                if let taxi = tfdm.taxiOutMinutes?.intValue {
                    StatusChip(text: "Taxi \(taxi) min", tone: .info, size: .mini)
                }
                if let wheels = tfdm.wheelsUpText {
                    StatusChip(text: "Wheels-up \(wheels)", tone: .info, size: .mini)
                }
                if let runway = tfdm.runwayAssigned, !runway.isEmpty {
                    StatusChip(text: "Rwy \(runway)", tone: .neutral, size: .mini)
                }
                Spacer(minLength: 0)
            }
            if let state = tfdm.flightState, !state.isEmpty {
                Text("State · \(state.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if let note = tfdm.note, !note.isEmpty {
                Text(note)
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func flowBlock<Content: View>(icon: String, title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        InsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    LucideIcon(name: icon, size: 13, fallback: "circle")
                        .foregroundStyle(Theme.teal)
                    GlossaryText(text: title, font: .caption.weight(.bold), color: Theme.ink)
                }
                content()
            }
        }
    }

    // MARK: - Loading

    private func loadFlow() {
        isLoading = true
        loadError = nil
        endpointMissing = false
        Task {
            let composed = await API.flowBrief(flight: flightIdent, date: date,
                                               originIcao: originIcao, destIcao: destIcao)
            switch composed {
            case .value(let envelope):
                brief = envelope
            case .missing:
                endpointMissing = true
                brief = await fallbackFromHelpers()
            case .failed(let message):
                // A 5xx / timeout on the composed route still deserves a
                // helper fallback — the individual SWIM feeds may be up.
                if let helper = await fallbackFromHelpers(), helper.hasContent {
                    brief = helper
                } else {
                    loadError = message
                }
            }
            isLoading = false
        }
    }

    /// Individual SWIM helpers when `/api/ops/flow-brief` is not deployed.
    /// Still user-initiated; still free; still slow.
    private func fallbackFromHelpers() async -> FlowBriefEnvelope? {
        let origin = originIcao
        let dest = destIcao ?? originIcao
        async let tfmsTask: SwimEnvelope? = {
            guard let airport = origin ?? dest else { return nil }
            return try? await API.tfmsFlow(airportIcao: airport, keyword: "GDP", duration: "8")
        }()
        async let tbfmTask: SwimEnvelope? = {
            guard let airport = dest else { return nil }
            return try? await API.tbfm(airportIcao: airport, flight: flightIdent, duration: "8")
        }()
        async let tfdmTask: SwimEnvelope? = {
            guard let airport = origin else { return nil }
            return try? await API.tfdm(airportIcao: airport, flight: flightIdent, duration: "8")
        }()
        let (tfms, tbfm, tfdm) = await (tfmsTask, tbfmTask, tfdmTask)
        if tfms == nil && tbfm == nil && tfdm == nil { return nil }
        return FlowBriefEnvelope.compose(tfms: tfms, tbfm: tbfm, tfdm: tfdm,
                                         flight: flightIdent, origin: origin, dest: dest)
    }
}

/// Compact CTOT / ATFM card. Shown only for European destinations when the
/// server verdict is PROBABLE or POSSIBLE — never invents a regulation.
struct AtfmCard: View {
    let atfm: AtfmEnvelope
    var embedded: Bool = false

    var body: some View {
        if atfm.shouldDisplay {
            let content = VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    LucideIcon(name: "timer", size: 16, fallback: "clock")
                        .foregroundStyle(Theme.gold)
                    GlossaryText(text: "ATFM / CTOT",
                                 font: TypeScale.sectionTitle,
                                 color: Theme.ink)
                    Spacer()
                    StatusChip(text: atfm.verdictCode,
                               tone: atfm.verdictCode == "PROBABLE" ? .watch : .info,
                               size: .mini, uppercased: true)
                }
                Text(atfm.headline)
                    .font(TypeScale.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let dest = atfm.destination {
                        StatusChip(text: dest, tone: .neutral, size: .mini)
                    }
                    if let delay = atfm.delayMinutes, delay > 0 {
                        StatusChip(text: "+\(delay) min vs schedule", tone: .watch, size: .mini)
                    }
                    Spacer(minLength: 0)
                }
                if let indicators = atfm.indicators, !indicators.isEmpty {
                    ForEach(Array(indicators.prefix(3).enumerated()), id: \.offset) { _, item in
                        if let detail = item.detail, !detail.isEmpty {
                            Text("· \(detail)")
                                .font(TypeScale.caption2)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
            if embedded {
                content
            } else {
                content.cardStyle()
            }
        }
    }
}

/// Open-Meteo / extended weather strip. Labelled "Model guidance" so it
/// never reads as a verdict driver. Hidden when the envelope is empty.
struct ModelGuidanceSection: View {
    let guidance: ModelGuidanceEnvelope
    var embedded: Bool = false

    var body: some View {
        if guidance.hasContent {
            let content = VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SectionHeader(icon: "line-chart", title: "Model guidance")
                    StatusChip(text: "Not a verdict driver", tone: .neutral, size: .mini)
                }
                Text(guidance.note
                     ?? "Numerical weather model (Open-Meteo) — situational context only. The brief's TAF windows are what can move the assessment.")
                    .font(TypeScale.caption2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(guidance.airports.enumerated()), id: \.offset) { _, airport in
                    HStack(alignment: .top, spacing: 8) {
                        if let icao = airport.icao {
                            Text(icao)
                                .font(TypeScale.captionBold)
                                .foregroundStyle(Theme.ink)
                                .frame(width: 48, alignment: .leading)
                        }
                        Text(airport.line)
                            .font(TypeScale.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                if let model = guidance.model, !model.isEmpty {
                    Text("Model · \(model.replacingOccurrences(of: "_", with: " "))")
                        .font(TypeScale.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            if embedded {
                content
            } else {
                content.cardStyle()
            }
        }
    }
}
