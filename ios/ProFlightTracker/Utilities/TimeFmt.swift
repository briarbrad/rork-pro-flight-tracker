import Foundation

/// Parsing and display helpers for the API's ISO 8601 timestamps.
nonisolated enum TimeFmt {
    /// Parses ISO 8601, tolerating trailing Z and fractional seconds.
    static func parseISO(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    /// "3:42 PM" in the given airport's zone, or "—" when missing.
    ///
    /// Passing `nil` yields Zulu ("20:45Z"), never device-local time: showing a
    /// Paris arrival in the phone's zone is the one failure mode that quietly
    /// tells the traveller the wrong hour.
    static func clock(_ iso: String?, zone: TimeZone? = nil) -> String {
        guard let date = parseISO(iso) else { return "—" }
        guard let zone else { return zulu(date) }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = zone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    /// "3:42 PM EDT" — time plus zone, matching the backend's `local_display`
    /// format so server- and client-resolved strings are indistinguishable.
    static func clockWithZone(_ iso: String?, zone: TimeZone?) -> String {
        guard let date = parseISO(iso) else { return "—" }
        guard let zone else { return zulu(date) }
        guard let label = zoneLabel(zone, at: date) else { return clock(iso, zone: zone) }
        return "\(clock(iso, zone: zone)) \(label)"
    }

    /// Short zone name at a specific instant — "EDT" in summer, "EST" in winter,
    /// "GMT+2" where no abbreviation exists.
    static func zoneLabel(_ zone: TimeZone?, at date: Date?) -> String? {
        guard let zone else { return "Z" }
        return zone.abbreviation(for: date ?? Date())
    }

    static func zoneLabel(_ zone: TimeZone?, atISO iso: String?) -> String? {
        zoneLabel(zone, at: parseISO(iso))
    }

    /// "20:45Z" — unambiguous everywhere, used whenever no airport zone is known.
    static func zulu(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm'Z'"
        return formatter.string(from: date)
    }

    /// "Tue Aug 18" in the airport's zone — for arrivals that land on the next
    /// calendar day locally.
    static func weekdayDate(_ iso: String?, zone: TimeZone?) -> String? {
        guard let date = parseISO(iso) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = zone ?? TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return formatter.string(from: date)
    }

    /// True when `iso` falls on a different local day than `reference` does in
    /// its own zone — i.e. the flight crosses midnight from the reader's view.
    static func crossesLocalDay(_ iso: String?, zone: TimeZone?,
                                reference: String?, referenceZone: TimeZone?) -> Bool {
        guard let date = parseISO(iso), let base = parseISO(reference) else { return false }
        var target = Calendar(identifier: .gregorian)
        target.timeZone = zone ?? TimeZone(identifier: "UTC")!
        var origin = Calendar(identifier: .gregorian)
        origin.timeZone = referenceZone ?? TimeZone(identifier: "UTC")!
        let lhs = target.dateComponents([.year, .month, .day], from: date)
        let rhs = origin.dateComponents([.year, .month, .day], from: base)
        return lhs != rhs
    }

    /// "Aug 16" style short date.
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    /// Relative description like "4m ago".
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Minutes between a scheduled and an effective (actual/estimated) time.
    static func slipMinutes(scheduled: String?, actual: String?, estimated: String?) -> Double? {
        guard let sched = parseISO(scheduled) else { return nil }
        guard let effective = parseISO(actual) ?? parseISO(estimated) else { return nil }
        return effective.timeIntervalSince(sched) / 60.0
    }

    /// Today's date in the API's yyyy-MM-dd format (UTC, matching the server).
    static func apiDate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
