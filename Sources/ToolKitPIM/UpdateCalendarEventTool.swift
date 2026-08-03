import Foundation
import FoundationModels

// REQ: FR-089 — update_calendar_event: patch an existing event by its stable id
// from list_calendar_events. Every patch field is optional; the tool reads the
// current event first and overlays only what changed (read-before-write, the
// file tools' contract, applied to the calendar).

@Generable
public struct UpdateCalendarEventArguments: Sendable {
    @Guide(description: "The [id] from list_calendar_events output")
    public var id: String
    @Guide(description: "New title")
    public var title: String?
    @Guide(description: "New start — ISO 8601 or a date")
    public var start: String?
    @Guide(description: "New end — ISO 8601 or a date")
    public var end: String?
    @Guide(description: "All-day (true/false)")
    public var all_day: Bool?
    @Guide(description: "New location; empty string clears it")
    public var location: String?
    @Guide(description: "New notes; empty string clears them")
    public var notes: String?
    @Guide(description: "Move to this calendar title (from list_calendars)")
    public var calendar: String?

    public init(
        id: String,
        title: String? = nil,
        start: String? = nil,
        end: String? = nil,
        all_day: Bool? = nil,
        location: String? = nil,
        notes: String? = nil,
        calendar: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.all_day = all_day
        self.location = location
        self.notes = notes
        self.calendar = calendar
    }
}

public struct UpdateCalendarEventTool: Tool, Sendable {
    public let name = "update_calendar_event"
    public let description = """
    Update an existing calendar event by its [id] from list_calendar_events. \
    Only the fields given change; an empty location or notes clears it. \
    Consequential — confirm with the user before calling. Requires the host \
    app's NSCalendarsFullAccessUsageDescription.
    """

    private let store: any CalendarEventStore
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(
        store: any CalendarEventStore = EventKitPIMStore(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.store = store
        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func call(arguments: UpdateCalendarEventArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("id must not be empty.")
        }
        let hasPatch = arguments.title != nil || arguments.start != nil || arguments.end != nil
            || arguments.all_day != nil || arguments.location != nil || arguments.notes != nil
            || arguments.calendar != nil
        guard hasPatch else {
            throw PIMToolError.invalidArguments("At least one field to update is required.")
        }
        guard let current = try await store.event(id: arguments.id) else {
            throw PIMToolError.notFound(kind: "calendar event", id: arguments.id)
        }
        let start = try arguments.start.map { try PIMDate.parse($0, calendar: calendar, timeZone: timeZone) }
            ?? current.startDate
        let end = try arguments.end.map { try PIMDate.parse($0, calendar: calendar, timeZone: timeZone) }
            ?? current.endDate
        guard end > start else {
            throw PIMToolError.invalidArguments("end must be after start.")
        }
        let event = try await store.updateEvent(id: arguments.id, PIMEventDraft(
            title: arguments.title.nilIfEmpty ?? current.title,
            startDate: start,
            endDate: end,
            isAllDay: arguments.all_day ?? current.isAllDay,
            location: arguments.location ?? current.location,
            notes: arguments.notes ?? current.notes,
            calendarTitle: arguments.calendar.nilIfEmpty ?? current.calendarTitle
        ))
        return "Updated \"\(event.title)\" [id: \(event.id ?? arguments.id)]"
    }
}
