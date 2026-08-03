import Foundation
import FoundationModels

// REQ: FR-096 — search_contacts: the read side of contacts. Matching by name,
// email, or phone (ANDed when more than one is given); the store applies the
// framework predicates so a large address book is never fully pulled.

@Generable
public struct SearchContactsArguments: Sendable {
    @Guide(description: "Search by name")
    public var name: String?
    @Guide(description: "Search by email address")
    public var email: String?
    @Guide(description: "Search by phone number")
    public var phone: String?
    @Guide(description: "Maximum contacts to return (default 20)")
    public var limit: Int?

    public init(name: String? = nil, email: String? = nil, phone: String? = nil, limit: Int? = nil) {
        self.name = name
        self.email = email
        self.phone = phone
        self.limit = limit
    }
}

public struct SearchContactsTool: Tool, Sendable {
    public let name = "search_contacts"
    public let description = """
    Search the user's contacts by name, email, or phone (at least one required; \
    combine to narrow). The [id] is the stable handle for update_contact and \
    delete_contact. Requires the host app's NSContactsUsageDescription.
    """

    private let store: any ContactStore

    public init(store: any ContactStore = ContactsPIMStore()) {
        self.store = store
    }

    public func call(arguments: SearchContactsArguments) async throws -> String {
        let name = arguments.name.nilIfEmpty
        let email = arguments.email.nilIfEmpty
        let phone = arguments.phone.nilIfEmpty
        guard name != nil || email != nil || phone != nil else {
            throw PIMToolError.invalidArguments("search_contacts needs at least one of name, email, or phone.")
        }
        let contacts = try await store.search(name: name, email: email, phone: phone)
        return PIMOutput.list(contacts, limit: max(1, arguments.limit ?? 20), line: PIMOutput.contactLine)
    }
}
