import Foundation
import FoundationModels

// REQ: FR-090 — delete_calendar_event: removes an event by its stable id from
// list_calendar_events. Reads the title first so the confirmation names what
// was deleted (and the not-found error is the tool's, not the store's).

@Generable
public struct DeleteCalendarEventArguments: Sendable {
    @Guide(description: "The [id] from list_calendar_events output")
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct DeleteCalendarEventTool: Tool, Sendable {
    public let name = "delete_calendar_event"
    public let description = """
    Delete a calendar event by its [id] from list_calendar_events. \
    Consequential and not reversible — confirm with the user before calling. \
    Requires the host app's NSCalendarsFullAccessUsageDescription.
    """

    private let store: any CalendarEventStore

    public init(store: any CalendarEventStore = EventKitPIMStore()) {
        self.store = store
    }

    public func call(arguments: DeleteCalendarEventArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("id must not be empty.")
        }
        guard let current = try await store.event(id: arguments.id) else {
            throw PIMToolError.notFound(kind: "calendar event", id: arguments.id)
        }
        try await store.deleteEvent(id: arguments.id)
        return "Deleted \"\(current.title)\""
    }
}
