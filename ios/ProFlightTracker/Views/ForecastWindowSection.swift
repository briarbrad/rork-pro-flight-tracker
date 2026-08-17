import SwiftUI

/// Terminal forecast for the ±60 minutes around each predicted time — the one
/// weather block that can move the verdict, and only through prevailing (FM)
/// conditions. TEMPO/PROB deteriorations are shown as a separate "may not
/// happen" line so a temporary group never reads like a replan trigger.
/// Categories and escalation are decided server-side; this view renders them.
struct ForecastWindowSection: View {
    let windows: BriefTafWindows

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "cloud-sun", title: "Forecast in your window")

            Text("What's forecast within an hour either side of the predicted times above — not the current weather.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)

            if let departure = windows.departure {
                WindowBlock(role: "Departure window", window: departure)
            }
            if windows.departure != nil && windows.arrival != nil {
                Divider().overlay(Theme.hairline)
            }
            if let arrival = windows.arrival {
                WindowBlock(role: "Arrival window", window: arrival)
            }
        }
        .cardStyle()
    }
}

/// One end of the trip: prevailing category headline, conditional watch line,
/// significant weather / gust / shear chips, and the forecast periods.
private struct WindowBlock: View {
    let role: String
    let window: BriefTafWindow

    @State private var showPeriods: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(role.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.inkSecondary)
                if let airport = window.airport {
                    GlossaryText(text: airport, font: .caption.weight(.semibold), color: Theme.ink)
                }
                Spacer()
                if window.isAvailable {
                    CategoryPill(category: window.prevailing, emphasized: window.prevailingEscalates)
                }
            }

            if window.isAvailable {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(window.prevailingEscalates ? Theme.red : Theme.ink)

                if window.hasConditionalDeterioration {
                    conditionalRow
                }

                if !chips.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.gold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.gold.opacity(0.12))
                                .clipShape(.capsule)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if let periods = window.periods, !periods.isEmpty {
                    Button {
                        Haptics.tap()
                        withAnimation(.snappy) { showPeriods.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showPeriods ? "Hide forecast periods" : "Forecast periods (\(periods.count))")
                                .font(.caption2.weight(.semibold))
                            LucideIcon(name: showPeriods ? "chevron-up" : "chevron-down",
                                       size: 10, fallback: "chevron.down")
                        }
                        .foregroundStyle(Theme.teal)
                    }
                    .buttonStyle(.plain)

                    if showPeriods {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(periods.enumerated()), id: \.offset) { _, period in
                                PeriodRow(period: period)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.canvas)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    LucideIcon(name: "telescope", size: 13, fallback: "eye.slash")
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 1)
                    GlossaryText(text: unavailableText, font: .caption2, color: Theme.inkSecondary)
                }
            }
        }
    }

    /// Reads the server's category decision back in plain English.
    private var headline: String {
        switch window.prevailing {
        case "LIFR": return "Forecast below minimums — expect holding, diversions, or an FAA program"
        case "IFR": return "Instrument conditions forecast — arrival rates drop and delays build"
        case "MVFR": return "Marginal ceilings forecast — routine, rarely delay-driving on its own"
        case "VFR": return "Clear flying conditions forecast through the window"
        default: return "Forecast category not determined"
        }
    }

    private var conditionalRow: some View {
        HStack(alignment: .top, spacing: 8) {
            LucideIcon(name: "eye", size: 13, fallback: "eye")
                .foregroundStyle(Theme.gold)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Could drop to")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                    CategoryPill(category: window.worstConditional, emphasized: false)
                }
                GlossaryText(text: "From a TEMPO/PROB group — a temporary deterioration that may not happen. Worth watching, not worth replanning.",
                             font: .caption2, color: Theme.inkSecondary)
            }
        }
    }

    private var chips: [String] {
        var items: [String] = (window.significantWeather ?? []).map { $0.capitalized }
        if let gust = window.gustText { items.append(gust) }
        if window.windShear == true { items.append("Wind shear") }
        return items
    }

    private var unavailableText: String {
        let note = window.note ?? ""
        return note.isEmpty ? "No terminal forecast covers this window yet." : note
    }
}

/// Flight-category pill; only prevailing IFR/LIFR gets the filled treatment,
/// mirroring what actually escalates the verdict server-side.
private struct CategoryPill: View {
    let category: String
    let emphasized: Bool

    private var color: Color {
        switch category {
        case "LIFR": return Theme.red
        case "IFR": return Theme.red
        case "MVFR": return Theme.gold
        case "VFR": return Theme.green
        default: return Theme.inkSecondary
        }
    }

    var body: some View {
        Text(category)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(emphasized ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(emphasized ? color : color.opacity(0.13))
            .clipShape(.capsule)
    }
}

/// One forecast period: local start time, group, category, and details.
private struct PeriodRow: View {
    let period: BriefTafPeriodWindow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(period.fromLocal ?? "—")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(period.groupLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(period.isConditional ? Theme.gold : Theme.inkSecondary)
            }
            .frame(width: 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    CategoryPill(category: period.categoryCode, emphasized: false)
                    if period.isConditional {
                        Text("temporary")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                if let detail = period.detailLine {
                    GlossaryText(text: detail, font: .caption2, color: Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
