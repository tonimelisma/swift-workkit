import Contacts
import Foundation

// REQ: ROADMAP item 3 — the Contacts-backed implementation of ContactStore.
// @unchecked Sendable for the same reason as EventKitPIMStore: CNContactStore is
// documented thread-safe, and the tool protocol requires Sendable. Reads fetch
// only the keys the tools format (no full address book pulled).

public final class ContactsPIMStore: ContactStore, @unchecked Sendable {
    private let store = CNContactStore()

    public init() {}

    private let fetchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]

    private func ensureAccess() async throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return
        case .notDetermined:
            guard try await store.requestAccess(for: .contacts) else {
                throw PIMToolError.accessDenied(framework: "Contacts", usageDescriptionKey: "NSContactsUsageDescription")
            }
        case .denied, .restricted:
            throw PIMToolError.accessDenied(framework: "Contacts", usageDescriptionKey: "NSContactsUsageDescription")
        @unknown default:
            throw PIMToolError.accessDenied(framework: "Contacts", usageDescriptionKey: "NSContactsUsageDescription")
        }
    }

    // MARK: - ContactStore

    public func search(name: String?, email: String?, phone: String?) async throws -> [PIMContact] {
        try await ensureAccess()
        var predicates: [NSPredicate] = []
        if let name { predicates.append(CNContact.predicateForContacts(matchingName: name)) }
        if let email { predicates.append(CNContact.predicateForContacts(matchingEmailAddress: email)) }
        if let phone { predicates.append(CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone))) }
        guard !predicates.isEmpty else {
            throw PIMToolError.invalidArguments("search_contacts needs at least one of name, email, or phone.")
        }
        let combined = predicates.count == 1 ? predicates[0]
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let contacts = try store.unifiedContacts(matching: combined, keysToFetch: fetchKeys)
        return contacts.map(pimContact(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func contact(id: String) async throws -> PIMContact? {
        try await ensureAccess()
        do {
            return pimContact(from: try store.unifiedContact(withIdentifier: id, keysToFetch: fetchKeys))
        } catch {
            // The Swift import of the nullable ObjC result is a thrown
            // "record does not exist" rather than a nil return; access was
            // already verified by ensureAccess(), so this is the not-found
            // path, not a permission edge.
            return nil
        }
    }

    public func createContact(_ draft: PIMContactDraft) async throws -> PIMContact {
        try await ensureAccess()
        let mutable = CNMutableContact()
        apply(draft, to: mutable)
        let request = CNSaveRequest()
        request.add(mutable, toContainerWithIdentifier: store.defaultContainerIdentifier())
        try store.execute(request)
        return pimContact(from: mutable)
    }

    public func updateContact(id: String, _ draft: PIMContactDraft) async throws -> PIMContact {
        try await ensureAccess()
        guard let existing = try? store.unifiedContact(withIdentifier: id, keysToFetch: fetchKeys) else {
            throw PIMToolError.notFound(kind: "contact", id: id)
        }
        let mutable = existing.mutableCopy() as! CNMutableContact
        apply(draft, to: mutable)
        let request = CNSaveRequest()
        request.update(mutable)
        try store.execute(request)
        return pimContact(from: mutable)
    }

    public func deleteContact(id: String) async throws {
        try await ensureAccess()
        guard let existing = try? store.unifiedContact(withIdentifier: id, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]) else {
            throw PIMToolError.notFound(kind: "contact", id: id)
        }
        let request = CNSaveRequest()
        request.delete(existing.mutableCopy() as! CNMutableContact)
        try store.execute(request)
    }

    // MARK: - Mapping

    /// Label-preserving apply: write `draft` onto `contact` while keeping
    /// existing email/phone labels on values the patch includes. `internal`
    /// so the suite can call it directly without an EventKit save round-trip
    /// (label state lives on `CNMutableContact`, not on `PIMContact` — there
    /// is no other offline evidence path).
    internal func apply(_ draft: PIMContactDraft, to contact: CNMutableContact) {
        contact.givenName = draft.givenName
        contact.familyName = draft.familyName
        contact.organizationName = draft.organization ?? ""
        contact.jobTitle = draft.jobTitle ?? ""
        contact.emailAddresses = Self.resolvedEmailLabels(existing: contact.emailAddresses, draft: draft.emails)
        contact.phoneNumbers = Self.resolvedPhoneLabels(existing: contact.phoneNumbers, draft: draft.phones)
    }

    /// Label-preserving apply for emails: a draft value equal (case-insensitive)
    /// to an existing entry keeps that entry's label; new values default to
    /// `CNLabelHome`. Empty / whitespace-only strings in the draft array are
    /// dropped — a model that passes `["ada@acme.com", ""]` shouldn't create a
    /// labeled empty-string entry.
    static func resolvedEmailLabels(
        existing: [CNLabeledValue<NSString>],
        draft: [String]
    ) -> [CNLabeledValue<NSString>] {
        let filtered = draft.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return filtered.map { value in
            let existingLabel = existing.first { entry in
                String(entry.value).caseInsensitiveCompare(value) == .orderedSame
            }?.label
            return CNLabeledValue(
                label: existingLabel ?? CNLabelHome,
                value: value as NSString
            )
        }
    }

    /// Label-preserving apply for phones: a draft value equal (string equality
    /// on `stringValue`) to an existing entry keeps that entry's label; new
    /// values default to `CNLabelPhoneNumberMobile`. Empty / whitespace-only
    /// strings in the draft array are dropped.
    static func resolvedPhoneLabels(
        existing: [CNLabeledValue<CNPhoneNumber>],
        draft: [String]
    ) -> [CNLabeledValue<CNPhoneNumber>] {
        let filtered = draft.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return filtered.map { value in
            let existingLabel = existing.first { entry in
                entry.value.stringValue == value
            }?.label
            return CNLabeledValue(
                label: existingLabel ?? CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: value)
            )
        }
    }

    private func pimContact(from contact: CNContact) -> PIMContact {
        let given = contact.givenName
        let family = contact.familyName
        let name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        let organization = contact.organizationName.isEmpty ? nil : contact.organizationName
        let displayName = name.isEmpty ? (organization ?? "Unnamed") : name
        return PIMContact(
            id: contact.identifier,
            name: displayName,
            givenName: given,
            familyName: family,
            organization: organization,
            jobTitle: contact.jobTitle.isEmpty ? nil : contact.jobTitle,
            emails: contact.emailAddresses.map { String($0.value) },
            phones: contact.phoneNumbers.map { $0.value.stringValue }
        )
    }
}
