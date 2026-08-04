import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-088 — create_calendar_event: the write half of the killer ask. The
// description states the consequence plainly; approval policy is host-supplied
// via ToolAnnotations (no annotations slot on the Tool protocol — see
// ENGINEERING.md "Tool tracing").

@Generable
public struct CreateCalendarEventArguments: Sendable {
    @Guide(description: "Event title")
    public var title: String
    @Guide(description: "Start — ISO 8601 (2026-08-02T15:00:00Z) or a date (2026-08-02)")
    public var start: String
    @Guide(description: "End — ISO 8601; must be after start")
    public var end: String
    @Guide(description: "All-day event (default false)")
    public var all_day: Bool?
    @Guide(description: "Location")
    public var location: String?
    @Guide(description: "Notes")
    public var notes: String?
    @Guide(description: "Calendar title, from list_calendars (default: first writable calendar)")
    public var calendar: String?

    public init(
        title: String,
        start: String,
        end: String,
        all_day: Bool? = nil,
        location: String? = nil,
        notes: String? = nil,
        calendar: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.all_day = all_day
        self.location = location
        self.notes = notes
        self.calendar = calendar
    }
}

public struct CreateCalendarEventTool: Tool, Sendable {
    public let name = "create_calendar_event"
    public let description = """
    Create an event in the user's calendar. Consequential — confirm with the \
    user before calling. Requires the host app's \
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

    public func call(arguments: CreateCalendarEventArguments) async throws -> String {
        guard arguments.title.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("title must not be empty.")
        }
        let start = try PIMDate.parse(arguments.start, calendar: calendar, timeZone: timeZone)
        let end = try PIMDate.parse(arguments.end, calendar: calendar, timeZone: timeZone)
        guard end > start else {
            throw PIMToolError.invalidArguments("end must be after start.")
        }
        let event = try await store.createEvent(PIMEventDraft(
            title: arguments.title,
            startDate: start,
            endDate: end,
            isAllDay: arguments.all_day ?? false,
            location: arguments.location.nilIfEmpty,
            notes: arguments.notes.nilIfEmpty,
            calendarTitle: arguments.calendar
        ))
        let range = event.isAllDay
            ? PIMDate.formatDay(event.startDate, timeZone: timeZone, locale: locale)
            : "\(PIMDate.format(event.startDate, timeZone: timeZone, locale: locale)) – \(PIMDate.format(event.endDate, timeZone: timeZone, locale: locale))"
        return "Created \"\(event.title)\" \(range) on \(event.calendarTitle) [id: \(event.id ?? "")]"
    }
}
