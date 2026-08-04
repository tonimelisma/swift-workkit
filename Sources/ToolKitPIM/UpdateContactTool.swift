import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-098 — update_contact: patch an existing contact by its stable id from
// search_contacts. Reads the current contact first and overlays only what
// changed (read-before-write); empty name strings clear a name field.

@Generable
public struct UpdateContactArguments: Sendable {
    @Guide(description: "The [id] from search_contacts output")
    public var id: String
    @Guide(description: "Given (first) name; empty string clears it")
    public var given_name: String?
    @Guide(description: "Family (last) name; empty string clears it")
    public var family_name: String?
    @Guide(description: "Organization; empty string clears it")
    public var organization: String?
    @Guide(description: "Job title; empty string clears it")
    public var job_title: String?
    @Guide(description: "Email addresses")
    public var emails: [String]?
    @Guide(description: "Phone numbers")
    public var phones: [String]?

    public init(
        id: String,
        given_name: String? = nil,
        family_name: String? = nil,
        organization: String? = nil,
        job_title: String? = nil,
        emails: [String]? = nil,
        phones: [String]? = nil
    ) {
        self.id = id
        self.given_name = given_name
        self.family_name = family_name
        self.organization = organization
        self.job_title = job_title
        self.emails = emails
        self.phones = phones
    }
}

public struct UpdateContactTool: Tool, Sendable {
    public let name = "update_contact"
    public let description = """
    Update an existing contact by its [id] from search_contacts. Only the \
    fields given change; an empty name field clears it. Consequential — confirm \
    with the user before calling. Requires the host app's NSContactsUsageDescription.
    """

    private let store: any ContactStore

    public init(store: any ContactStore = ContactsPIMStore()) {
        self.store = store
    }

    public func call(arguments: UpdateContactArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw PIMToolError.invalidArguments("id must not be empty.")
        }
        let hasPatch = arguments.given_name != nil || arguments.family_name != nil
            || arguments.organization != nil || arguments.job_title != nil
            || arguments.emails != nil || arguments.phones != nil
        guard hasPatch else {
            throw PIMToolError.invalidArguments("At least one field to update is required.")
        }
        guard let current = try await store.contact(id: arguments.id) else {
            throw PIMToolError.notFound(kind: "contact", id: arguments.id)
        }
        // Empty-clears contract (Toni 2026-08-03 delegated; matches the calendar
        // tool's location/notes overlay and the file-tool edit ledger): nil
        // preserves the current value; empty / whitespace clears — to `""` for
        // a non-optional String field, to `nil` for an optional one.
        let givenName  = arguments.given_name.map  { $0.nilIfEmpty ?? "" } ?? current.givenName
        let familyName = arguments.family_name.map { $0.nilIfEmpty ?? "" } ?? current.familyName
        let organization = arguments.organization.map { $0.nilIfEmpty } ?? current.organization
        let jobTitle   = arguments.job_title.map   { $0.nilIfEmpty } ?? current.jobTitle
        let draft = PIMContactDraft(
            givenName: givenName,
            familyName: familyName,
            organization: organization,
            jobTitle: jobTitle,
            emails: arguments.emails ?? current.emails,
            phones: arguments.phones ?? current.phones
        )
        guard draft.hasAnyValue else {
            throw PIMToolError.invalidArguments(
                "A contact needs a name or an organization."
            )
        }
        let contact = try await store.updateContact(id: arguments.id, draft)
        return "Updated \"\(contact.name)\" [id: \(contact.id)]"
    }
}
