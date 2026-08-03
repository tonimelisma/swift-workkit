import Foundation
import FoundationModels

// REQ: FR-091 — list_reminders: overdue/upcoming/past at a glance, and the
// read-before-write source for complete/uncomplete/delete (the id comes from here).

@Generable
public struct ListRemindersArguments: Sendable {
    @Guide(description: "Which reminders: 'incomplete' (default), 'completed', or 'all'")
    public var state: String?
    @Guide(description: "Only reminders due at or after this — ISO 8601 or a date")
    public var due_from: String?
    @Guide(description: "Only reminders due before this — ISO 8601 or a date")
    public var due_to: String?
    @Guide(description: "Reminder-list titles to include; default: all lists")
    public var lists: [String]?
    @Guide(description: "Maximum reminders to return (default 50)")
    public var limit: Int?

    public init(
        state: String? = nil,
        due_from: String? = nil,
        due_to: String? = nil,
        lists: [String]? = nil,
        limit: Int? = nil
    ) {
        self.state = state
        self.due_from = due_from
        self.due_to = due_to
        self.lists = lists
        self.limit = limit
    }
}

public struct ListRemindersTool: Tool, Sendable {
    public let name = "list_reminders"
    public let description = """
    List the user's reminders, sorted by due date (undated last). The default \
    state is 'incomplete'. The [id] is the stable handle for \
    complete_reminder, uncomplete_reminder, and delete_reminder. Requires the \
    host app's NSRemindersFullAccessUsageDescription.
    """

    private let store: any ReminderStore
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let locale: Locale

    public init(
        store: any ReminderStore = EventKitPIMStore(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        self.store = store
        self.calendar = calendar
        self.timeZone = timeZone
        self.locale = locale
    }

    public func call(arguments: ListRemindersArguments) async throws -> String {
        let state: ReminderFilterState
        switch arguments.state?.lowercased() {
        case nil, "incomplete": state = .incomplete
        case "completed": state = .completed
        case "all": state = .all
        case let other?:
            throw PIMToolError.invalidArguments("state must be 'incomplete', 'completed', or 'all'; got '\(other)'.")
        }
        let dueFrom = try arguments.due_from.map { try PIMDate.parse($0, calendar: calendar, timeZone: timeZone) }
        let dueTo = try arguments.due_to.map { try PIMDate.parse($0, calendar: calendar, timeZone: timeZone) }
        if let dueFrom, let dueTo, dueFrom >= dueTo {
            throw PIMToolError.invalidArguments("due_to must be after due_from.")
        }
        let reminders = try await store.reminders(
            state: state, dueFrom: dueFrom, dueTo: dueTo, calendarTitles: arguments.lists
        )
        return PIMOutput.list(reminders, limit: max(1, arguments.limit ?? 50)) {
            PIMOutput.reminderLine($0, timeZone: timeZone, locale: locale)
        }
    }
}
