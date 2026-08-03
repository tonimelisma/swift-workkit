import Foundation
import Testing
@testable import ToolKitPIM

// REQ: FR-096..FR-099 — contact tool contracts against in-memory doubles.

@Test("FR-096: search_contacts requires at least one criterion")
func searchRequiresCriterion() async throws {
    let tool = SearchContactsTool(store: MemoryContactStore())
    await #expect(throws: PIMToolError.invalidArguments("search_contacts needs at least one of name, email, or phone.")) {
        _ = try await tool.call(arguments: .init())
    }
}

@Test("FR-096: search_contacts formats names, details, and ids")
func searchFormats() async throws {
    let store = MemoryContactStore(contacts: [
        PIMContact(id: "c1", name: "Ada Lovelace", givenName: "Ada", familyName: "Lovelace", organization: "Acme", jobTitle: "Engineer", emails: ["ada@acme.com"], phones: ["+1-555-0100"]),
    ])
    let tool = SearchContactsTool(store: store)
    let output = try await tool.call(arguments: .init(name: "ada"))
    #expect(output.contains("1. Ada Lovelace — Acme · Engineer"))
    #expect(output.contains("Emails: ada@acme.com"))
    #expect(output.contains("Phones: +1-555-0100"))
    #expect(output.contains("[id: c1]"))
}

@Test("FR-096: search_contacts passes email and phone criteria through")
func searchPassesCriteria() async throws {
    let store = MemoryContactStore(contacts: [
        PIMContact(id: "c1", name: "Grace Hopper", givenName: "Grace", familyName: "Hopper", organization: nil, jobTitle: nil, emails: ["grace@navy.mil"], phones: ["+1-555-0101"]),
    ])
    let tool = SearchContactsTool(store: store)
    let byEmail = try await tool.call(arguments: .init(email: "grace@navy.mil"))
    #expect(byEmail.contains("Grace Hopper"))
    let byPhone = try await tool.call(arguments: .init(phone: "+1-555-0101"))
    #expect(byPhone.contains("Grace Hopper"))
}

@Test("FR-097: create_contact rejects a nameless contact")
func createContactRejectsEmpty() async throws {
    let tool = CreateContactTool(store: MemoryContactStore())
    await #expect(throws: PIMToolError.invalidArguments("create_contact needs a name or an organization.")) {
        _ = try await tool.call(arguments: .init(emails: ["x@y.com"]))
    }
}

@Test("FR-097: create_contact builds the draft and reports the id")
func createContactBuildsDraft() async throws {
    let store = MemoryContactStore()
    let tool = CreateContactTool(store: store)
    let output = try await tool.call(arguments: .init(
        given_name: "Ada", family_name: "Lovelace", organization: "Acme",
        job_title: "Engineer", emails: ["ada@acme.com"], phones: ["+1-555-0100"]
    ))
    #expect(output == "Created \"Ada Lovelace\" [id: ctc1]")
    #expect(store.lastCreateDraft?.givenName == "Ada")
    #expect(store.lastCreateDraft?.organization == "Acme")
    #expect(store.lastCreateDraft?.emails == ["ada@acme.com"])
}

@Test("FR-098: update_contact rejects an empty patch and a missing id")
func updateContactRejects() async throws {
    let store = MemoryContactStore()
    let tool = UpdateContactTool(store: store)
    await #expect(throws: PIMToolError.invalidArguments("At least one field to update is required.")) {
        _ = try await tool.call(arguments: .init(id: "c1"))
    }
    await #expect(throws: PIMToolError.notFound(kind: "contact", id: "gone")) {
        _ = try await tool.call(arguments: .init(id: "gone", job_title: "X"))
    }
}

@Test("FR-098: update_contact overlays patches on the current contact")
func updateContactOverlays() async throws {
    let store = MemoryContactStore(contacts: [
        PIMContact(id: "c1", name: "Ada Lovelace", givenName: "Ada", familyName: "Lovelace", organization: "Acme", jobTitle: "Engineer", emails: ["ada@acme.com"], phones: []),
    ])
    let tool = UpdateContactTool(store: store)
    let output = try await tool.call(arguments: .init(id: "c1", job_title: "Staff Engineer"))
    #expect(output == "Updated \"Ada Lovelace\" [id: c1]")
    #expect(store.lastUpdateDraft?.jobTitle == "Staff Engineer")
    #expect(store.lastUpdateDraft?.givenName == "Ada")
    #expect(store.lastUpdateDraft?.emails == ["ada@acme.com"])
}

@Test("FR-099: delete_contact reports a missing id and confirms by name")
func deleteContactBehavior() async throws {
    let store = MemoryContactStore()
    let tool = DeleteContactTool(store: store)
    await #expect(throws: PIMToolError.notFound(kind: "contact", id: "gone")) {
        _ = try await tool.call(arguments: .init(id: "gone"))
    }
    store.contactsByID = ["c1": PIMContact(id: "c1", name: "Grace Hopper", givenName: "Grace", familyName: "Hopper", organization: nil, jobTitle: nil, emails: [], phones: [])]
    let output = try await tool.call(arguments: .init(id: "c1"))
    #expect(output == "Deleted \"Grace Hopper\"")
    #expect(store.lastDeletedID == "c1")
}

@Test("FR-096: an access denial from the store propagates named")
func contactAccessDenialPropagates() async throws {
    let store = MemoryContactStore()
    store.injectedError = PIMToolError.accessDenied(framework: "Contacts", usageDescriptionKey: "NSContactsUsageDescription")
    let tool = SearchContactsTool(store: store)
    await #expect(throws: PIMToolError.accessDenied(framework: "Contacts", usageDescriptionKey: "NSContactsUsageDescription")) {
        _ = try await tool.call(arguments: .init(name: "ada"))
    }
}
