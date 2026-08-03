import Foundation

// REQ: ROADMAP item 3 — `@Generable` has no Date conformance (verified in both
// OS 27 swiftinterfaces: Bool/String/Int/Float/Double/Decimal/Array/Optional/
// Never only), so dates travel as ISO 8601 strings in tool arguments and are
// parsed here. `Date.FormatStyle` does the output side so formatting respects
// the user's locale and calendar.

enum PIMDate {
    /// Accepts a full ISO 8601 date-time (`2026-08-02T15:00:00Z`) or a bare
    /// date (`2026-08-02`) meaning that day at local midnight, in `timeZone`.
    static func parse(_ raw: String, calendar: Calendar, timeZone: TimeZone) throws -> Date {
        var style = Date.ISO8601FormatStyle()
        style.timeZone = timeZone
        if let date = try? Date(raw, strategy: style) {
            return date
        }
        let parts = raw.split(separator: "-")
        if parts.count == 3,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.timeZone = timeZone
            if let date = calendar.date(from: components) {
                return date
            }
        }
        throw PIMToolError.invalidArguments(
            "Couldn't parse '\(raw)' as a date. Use ISO 8601 (2026-08-02T15:00:00Z) or a date (2026-08-02)."
        )
    }

    static func format(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
    }

    static func formatDay(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone))
    }

    static func formatTime(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
