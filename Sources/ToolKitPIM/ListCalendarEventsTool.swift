import Foundation
import FoundationModels

// REQ: FR-087 — list_calendar_events: the "What's on my calendar" killer ask,
// and the read-before-write source for update/delete (the id comes from here).

@Generable
public struct ListCalendarEventsArguments: Sendable {
    @Guide(description: "Start of the range — ISO 8601 (2026-08-02T15:00:00Z) or a date (2026-08-02); default: today at local midnight")
    public var start: String?
    @Guide(description: "End of the range, exclusive — same format; default: start + 1 day")
    public var end: String?
    @Guide(description: "Calendar titles to include; default: all calendars")
    public var calendars: [String]?
    @Guide(description: "Maximum events to return (default 50)")
    public var limit: Int?

    public init(start: String? = nil, end: String? = nil, calendars: [String]? = nil, limit: Int? = nil) {
        self.start = start
        self.end = end
        self.calendars = calendars
        self.limit = limit
    }
}

public struct ListCalendarEventsTool: Tool, Sendable {
    public let name = "list_calendar_events"
    public let description = """
    List the user's calendar events in a date range, sorted by start time. The \
    default range is today. The [id] is the stable handle for \
    update_calendar_event and delete_calendar_event. Requires the host app's \
    NSCalendarsFullAccessUsageDescription.
    """

    private let store: any CalendarEventStore
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let locale: Locale

    public init(
        store: any CalendarEventStore = EventKitPIMStore(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        self.store = store
        self.calendar = calendar
        self.timeZone = timeZone
        self.locale = locale
    }

    public func call(arguments: ListCalendarEventsArguments) async throws -> String {
        let start = try arguments.start
            .map { try PIMDate.parse($0, calendar: calendar, timeZone: timeZone) }
            ?? calendar.startOfDay(for: Date())
        let end = try arguments.end
            .map { try PIMDate.parse($0, calendar: calendar, timeZone: timeZone) }
            ?? (calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
        guard end > start else {
            throw PIMToolError.invalidArguments("end must be after start.")
        }
        let events = try await store.events(from: start, to: end, calendarTitles: arguments.calendars)
        return PIMOutput.list(events, limit: max(1, arguments.limit ?? 50)) {
            PIMOutput.eventLine($0, calendar: calendar, timeZone: timeZone, locale: locale)
        }
    }
}
