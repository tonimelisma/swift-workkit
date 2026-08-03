import Foundation
import FoundationModels

// REQ: FR-086 — list_calendars: the handle source for every calendar tool. The
// model sees titles (the write tools' `calendar` argument) and stable IDs (the
// update/delete handle), and "read-only" flags a calendar the write tools will
// refuse.

@Generable
public struct ListCalendarsArguments: Sendable {
    @Guide(description: "Which set to list: 'event' (default) or 'reminder'")
    public var entity: String?

    public init(entity: String? = nil) {
        self.entity = entity
    }
}

public struct ListCalendarsTool: Tool, Sendable {
    public let name = "list_calendars"
    public let description = """
    List the user's event calendars (default) or reminder lists ('reminder'). \
    Titles here are what the write tools' 'calendar'/'list' argument accepts; \
    the [id] is the stable handle. Requires the host app's \
    NSCalendarsFullAccessUsageDescription (event) or \
    NSRemindersFullAccessUsageDescription (reminder).
    """

    private let eventStore: any CalendarEventStore
    private let reminderStore: any ReminderStore

    public init(
        eventStore: any CalendarEventStore = EventKitPIMStore(),
        reminderStore: any ReminderStore = EventKitPIMStore()
    ) {
        self.eventStore = eventStore
        self.reminderStore = reminderStore
    }

    public func call(arguments: ListCalendarsArguments) async throws -> String {
        switch arguments.entity?.lowercased() {
        case nil, "event":
            let calendars = try await eventStore.calendars()
            return PIMOutput.list(calendars, limit: 100, line: PIMOutput.calendarLine)
        case "reminder":
            let lists = try await reminderStore.calendarLists()
            return PIMOutput.list(lists, limit: 100, line: PIMOutput.calendarLine)
        case let other?:
            throw PIMToolError.invalidArguments(
                "entity must be 'event' or 'reminder'; got '\(other)'."
            )
        }
    }
}
