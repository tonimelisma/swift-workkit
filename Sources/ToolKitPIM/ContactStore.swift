import Foundation

// REQ: ROADMAP item 3 — the contacts seam (see CalendarEventStore.swift for why
// a seam). The concrete Contacts-backed store lives in ContactsPIMStore.swift.

public protocol ContactStore: Sendable {
    /// Contacts matching at least one of name/email/phone (the tool validates
    /// that at least one is present), sorted by display name.
    func search(name: String?, email: String?, phone: String?) async throws -> [PIMContact]
    /// One contact by stable id, or nil. Update tools read-before-write with it.
    func contact(id: String) async throws -> PIMContact?
    /// Creates a contact in the default container.
    func createContact(_ draft: PIMContactDraft) async throws -> PIMContact
    /// Replaces the contact `id`'s fields with the draft (the tool overlays
    /// patches onto the current contact before calling).
    func updateContact(id: String, _ draft: PIMContactDraft) async throws -> PIMContact
    /// Deletes the contact `id`.
    func deleteContact(id: String) async throws
}
