import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-093 — complete_reminder: idempotent by design. The explicit
// final-state check below (guard !current.isCompleted) skips the setCompleted
// write when the reminder is already done, so a redundant call reports "was
// already completed" rather than re-issuing a write — the source of the
// idempotency is this check, not the Recorder's journal-before-execute guard.

@Generable
public struct CompleteReminderArguments: Sendable {
    @Guide(description: "The [id] from list_reminders output")
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct CompleteReminderTool: Tool, Sendable {
    public let name = "complete_reminder"
    public let description = """
    Mark a reminder as completed, by its [id] from list_reminders. Already \
    completed reminders are reported as such. Requires the host app's \
    NSRemindersFullAccessUsageDescription.
    """

    private let store: any ReminderStore

    public init(store: any ReminderStore = EventKitPIMStore()) {
        self.store = store
    }

    public func call(arguments: CompleteReminderArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("id must not be empty.")
        }
        guard let current = try await store.reminder(id: arguments.id) else {
            throw PIMToolError.notFound(kind: "reminder", id: arguments.id)
        }
        guard !current.isCompleted else {
            return "\"\(current.title)\" was already completed."
        }
        let reminder = try await store.setCompleted(true, reminderID: arguments.id)
        return "Completed \"\(reminder.title)\""
    }
}
