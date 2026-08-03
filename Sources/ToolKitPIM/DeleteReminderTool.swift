import Foundation
import FoundationModels

// REQ: FR-095 — delete_reminder: removes a reminder by its stable id from
// list_reminders. Reads the title first so the confirmation names what was
// deleted.

@Generable
public struct DeleteReminderArguments: Sendable {
    @Guide(description: "The [id] from list_reminders output")
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct DeleteReminderTool: Tool, Sendable {
    public let name = "delete_reminder"
    public let description = """
    Delete a reminder by its [id] from list_reminders. Consequential and not \
    reversible — confirm with the user before calling. Requires the host app's \
    NSRemindersFullAccessUsageDescription.
    """

    private let store: any ReminderStore

    public init(store: any ReminderStore = EventKitPIMStore()) {
        self.store = store
    }

    public func call(arguments: DeleteReminderArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("id must not be empty.")
        }
        guard let current = try await store.reminder(id: arguments.id) else {
            throw PIMToolError.notFound(kind: "reminder", id: arguments.id)
        }
        try await store.deleteReminder(id: arguments.id)
        return "Deleted \"\(current.title)\""
    }
}
