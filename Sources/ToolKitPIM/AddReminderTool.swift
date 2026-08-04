import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-092 — add_reminder: the write side of reminders. Like the calendar
// write tools, the description names the consequence and the TCC key.

@Generable
public struct AddReminderArguments: Sendable {
    @Guide(description: "Reminder text")
    public var title: String
    @Guide(description: "Notes")
    public var notes: String?
    @Guide(description: "Due date — ISO 8601 or a date")
    public var due: String?
    @Guide(description: "Reminder-list title, from list_calendars 'reminder' (default: first writable list)")
    public var list: String?

    public init(title: String, notes: String? = nil, due: String? = nil, list: String? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
        self.list = list
    }
}

public struct AddReminderTool: Tool, Sendable {
    public let name = "add_reminder"
    public let description = """
    Add a reminder to the user's list. Consequential — confirm with the user \
    before calling. Requires the host app's NSRemindersFullAccessUsageDescription.
    """

    private let store: any ReminderStore
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(
        store: any ReminderStore = EventKitPIMStore(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.store = store
        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func call(arguments: AddReminderArguments) async throws -> String {
        guard arguments.title.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("title must not be empty.")
        }
        let due = try arguments.due.map { try PIMDate.parse($0, calendar: calendar, timeZone: timeZone) }
        let reminder = try await store.createReminder(PIMReminderDraft(
            title: arguments.title,
            notes: arguments.notes.nilIfEmpty,
            dueDate: due,
            calendarTitle: arguments.list
        ))
        return "Added \"\(reminder.title)\" [id: \(reminder.id)]"
    }
}
