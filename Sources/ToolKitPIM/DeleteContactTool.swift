import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-099 — delete_contact: removes a contact by its stable id from
// search_contacts. Reads the name first so the confirmation names who.

@Generable
public struct DeleteContactArguments: Sendable {
    @Guide(description: "The [id] from search_contacts output")
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct DeleteContactTool: Tool, Sendable {
    public let name = "delete_contact"
    public let description = """
    Delete a contact by its [id] from search_contacts. Consequential and not \
    reversible — confirm with the user before calling. Requires the host app's \
    NSContactsUsageDescription.
    """

    private let store: any ContactStore

    public init(store: any ContactStore = ContactsPIMStore()) {
        self.store = store
    }

    public func call(arguments: DeleteContactArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("id must not be empty.")
        }
        guard let current = try await store.contact(id: arguments.id) else {
            throw PIMToolError.notFound(kind: "contact", id: arguments.id)
        }
        try await store.deleteContact(id: arguments.id)
        return "Deleted \"\(current.name)\""
    }
}
