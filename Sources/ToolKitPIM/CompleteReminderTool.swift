import Foundation
import FoundationModels

// REQ: FR-093 — complete_reminder: idempotent by design (completing an already
// completed reminder is a no-op the tool reports as such), so the journal-
// before-execute guard never double-completes something already done.

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
