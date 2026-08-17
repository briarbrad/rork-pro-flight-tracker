import SwiftUI

/// Single source of truth for how bad a schedule slip is: watch at >=15 min,
/// alert at >=45 min. Every delay judgement — time tints, slip chips, risk
/// signals, inbound-late checks — reads these thresholds, never its own.
enum SlipSeverity {
    case none, watch, alert

    static let watchThresholdMin: Double = 15
    static let alertThresholdMin: Double = 45

    static func of(minutes: Double?) -> SlipSeverity {
        guard let minutes else { return .none }
        if minutes >= alertThresholdMin { return .alert }
        if minutes >= watchThresholdMin { return .watch }
        return .none
    }

    /// Severity of the gap between a scheduled ISO time and the effective
    /// (actual or estimated) one.
    static func of(scheduled: String?, effective: String?) -> SlipSeverity {
        guard let sched = TimeFmt.parseISO(scheduled),
              let eff = TimeFmt.parseISO(effective) else { return .none }
        return of(minutes: eff.timeIntervalSince(sched) / 60)
    }

    var isSlipped: Bool { self != .none }

    /// AA-safe text tint for a slipped time; `base` when on schedule.
    func textColor(default base: Color) -> Color {
        switch self {
        case .alert: return Theme.red
        case .watch: return Theme.goldText
        case .none: return base
        }
    }
}
