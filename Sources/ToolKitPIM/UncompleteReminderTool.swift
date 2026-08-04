import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-094 — uncomplete_reminder: the re-open that keeps a check-off honest —
// a completed-in-error reminder comes back, and the report says exactly that.

@Generable
public struct UncompleteReminderArguments: Sendable {
    @Guide(description: "The [id] from list_reminders output")
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct UncompleteReminderTool: Tool, Sendable {
    public let name = "uncomplete_reminder"
    public let description = """
    Re-open a completed reminder, by its [id] from list_reminders. Already open \
    reminders are reported as such. Requires the host app's \
    NSRemindersFullAccessUsageDescription.
    """

    private let store: any ReminderStore

    public init(store: any ReminderStore = EventKitPIMStore()) {
        self.store = store
    }

    public func call(arguments: UncompleteReminderArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("id must not be empty.")
        }
        guard let current = try await store.reminder(id: arguments.id) else {
            throw PIMToolError.notFound(kind: "reminder", id: arguments.id)
        }
        guard current.isCompleted else {
            return "\"\(current.title)\" was already open."
        }
        let reminder = try await store.setCompleted(false, reminderID: arguments.id)
        return "Reopened \"\(reminder.title)\""
    }
}
