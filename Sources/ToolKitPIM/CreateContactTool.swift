import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-097 — create_contact: the write side of contacts. A contact with no
// name and no organization is rejected — there is nothing to call it by.

@Generable
public struct CreateContactArguments: Sendable {
    @Guide(description: "Given (first) name")
    public var given_name: String?
    @Guide(description: "Family (last) name")
    public var family_name: String?
    @Guide(description: "Organization")
    public var organization: String?
    @Guide(description: "Job title")
    public var job_title: String?
    @Guide(description: "Email addresses")
    public var emails: [String]?
    @Guide(description: "Phone numbers")
    public var phones: [String]?

    public init(
        given_name: String? = nil,
        family_name: String? = nil,
        organization: String? = nil,
        job_title: String? = nil,
        emails: [String]? = nil,
        phones: [String]? = nil
    ) {
        self.given_name = given_name
        self.family_name = family_name
        self.organization = organization
        self.job_title = job_title
        self.emails = emails
        self.phones = phones
    }
}

public struct CreateContactTool: Tool, Sendable {
    public let name = "create_contact"
    public let description = """
    Create a contact in the user's address book. Consequential — confirm with \
    the user before calling. Requires the host app's NSContactsUsageDescription.
    """

    private let store: any ContactStore

    public init(store: any ContactStore = ContactsPIMStore()) {
        self.store = store
    }

    public func call(arguments: CreateContactArguments) async throws -> String {
        let draft = PIMContactDraft(
            givenName: arguments.given_name.nilIfEmpty ?? "",
            familyName: arguments.family_name.nilIfEmpty ?? "",
            organization: arguments.organization.nilIfEmpty,
            jobTitle: arguments.job_title.nilIfEmpty,
            emails: arguments.emails ?? [],
            phones: arguments.phones ?? []
        )
        guard draft.hasAnyValue else {
            throw PIMToolError.invalidArguments(
                "create_contact needs a name or an organization."
            )
        }
        let contact = try await store.createContact(draft)
        return "Created \"\(contact.name)\" [id: \(contact.id)]"
    }
}
