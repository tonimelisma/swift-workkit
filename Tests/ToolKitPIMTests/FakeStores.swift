import Foundation
@testable import ToolKitPIM

// REQ: ROADMAP item 3 — in-memory store doubles. The tools' contract tests
// assert argument handling, draft construction, and output formatting against
// these; the framework-backed stores are exercised only by a host (TCC makes
// the live path unautomatable). @unchecked Sendable because the tools require
// Sendable stores and the doubles are single-threaded test fixtures.

let fixedTimeZone = TimeZone(secondsFromGMT: 0)!
let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = fixedTimeZone
    return calendar
}()
let fixedLocale = Locale(identifier: "en_US_POSIX")

/// Locale typography uses a narrow no-break space (U+202F) before AM/PM;
/// normalize it so date-format assertions stay readable.
func normalized(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")
}

final class MemoryCalendarStore: CalendarEventStore, @unchecked Sendable {
    var calendarsList: [PIMCalendar]
    private var eventsByID: [String: PIMEvent]
    var injectedError: PIMToolError?
    var lastCreateDraft: PIMEventDraft?
    var lastUpdateDraft: PIMEventDraft?
    var lastDeletedID: String?
    private var nextID = 1

    init(calendarsList: [PIMCalendar] = [], events: [PIMEvent] = []) {
        self.calendarsList = calendarsList
        self.eventsByID = [:]
        for event in events {
            if let id = event.id { eventsByID[id] = event }
        }
    }

    func calendars() async throws -> [PIMCalendar] {
        if let injectedError { throw injectedError }
        return calendarsList
    }

    func events(from start: Date, to end: Date, calendarTitles: [String]?) async throws -> [PIMEvent] {
        if let injectedError { throw injectedError }
        return eventsByID.values
            // Mirror EventKit `predicateForEvents(withStart:end:calendars:)`:
            // an event whose own range overlaps the query range is returned —
            // not only events whose `startDate` falls inside it. A multi-day
            // event starting yesterday shows up under today's query.
            .filter { event in event.startDate < end && event.endDate > start }
            .filter { event in
                calendarTitles?.contains { $0.caseInsensitiveCompare(event.calendarTitle) == .orderedSame } ?? true
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func event(id: String) async throws -> PIMEvent? {
        eventsByID[id]
    }

    func createEvent(_ draft: PIMEventDraft) async throws -> PIMEvent {
        lastCreateDraft = draft
        let id = "evt\(nextID)"; nextID += 1
        let event = PIMEvent(
            id: id, title: draft.title, startDate: draft.startDate, endDate: draft.endDate,
            isAllDay: draft.isAllDay, location: draft.location, notes: draft.notes,
            calendarTitle: draft.calendarTitle ?? "Default"
        )
        eventsByID[id] = event
        return event
    }

    func updateEvent(id: String, _ draft: PIMEventDraft) async throws -> PIMEvent {
        lastUpdateDraft = draft
        guard let current = eventsByID[id] else {
            throw PIMToolError.notFound(kind: "calendar event", id: id)
        }
        let event = PIMEvent(
            id: id, title: draft.title, startDate: draft.startDate, endDate: draft.endDate,
            isAllDay: draft.isAllDay, location: draft.location, notes: draft.notes,
            calendarTitle: draft.calendarTitle ?? current.calendarTitle
        )
        eventsByID[id] = event
        return event
    }

    func deleteEvent(id: String) async throws {
        lastDeletedID = id
        guard eventsByID[id] != nil else {
            throw PIMToolError.notFound(kind: "calendar event", id: id)
        }
        eventsByID[id] = nil
    }
}

final class MemoryReminderStore: ReminderStore, @unchecked Sendable {
    var lists: [PIMCalendar]
    private var remindersByID: [String: PIMReminder]
    var injectedError: PIMToolError?
    var lastCreateDraft: PIMReminderDraft?
    var lastToggled: (id: String, completed: Bool)?
    var lastDeletedID: String?
    private var nextID = 1

    init(lists: [PIMCalendar] = [], reminders: [PIMReminder] = []) {
        self.lists = lists
        self.remindersByID = [:]
        for reminder in reminders { remindersByID[reminder.id] = reminder }
    }

    func calendarLists() async throws -> [PIMCalendar] {
        if let injectedError { throw injectedError }
        return lists
    }

    func reminders(state: ReminderFilterState, dueFrom: Date?, dueTo: Date?, calendarTitles: [String]?) async throws -> [PIMReminder] {
        if let injectedError { throw injectedError }
        return remindersByID.values
            .filter { state == .all || $0.isCompleted == (state == .completed) }
            .filter { reminder in
                calendarTitles?.contains { $0.caseInsensitiveCompare(reminder.calendarTitle) == .orderedSame } ?? true
            }
            .filter { reminder in
                guard let due = reminder.dueDate else { return true }
                if let dueFrom, due < dueFrom { return false }
                if let dueTo, due >= dueTo { return false }
                return true
            }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l < r
                case (nil, nil): return lhs.title < rhs.title
                case (nil, _): return false
                case (_, nil): return true
                }
            }
    }

    func reminder(id: String) async throws -> PIMReminder? {
        remindersByID[id]
    }

    func createReminder(_ draft: PIMReminderDraft) async throws -> PIMReminder {
        lastCreateDraft = draft
        let id = "rmd\(nextID)"; nextID += 1
        let reminder = PIMReminder(
            id: id, title: draft.title, notes: draft.notes, dueDate: draft.dueDate,
            isCompleted: false, completionDate: nil, calendarTitle: draft.calendarTitle ?? "Reminders"
        )
        remindersByID[id] = reminder
        return reminder
    }

    func setCompleted(_ completed: Bool, reminderID: String) async throws -> PIMReminder {
        lastToggled = (reminderID, completed)
        guard let current = remindersByID[reminderID] else {
            throw PIMToolError.notFound(kind: "reminder", id: reminderID)
        }
        let reminder = PIMReminder(
            id: current.id, title: current.title, notes: current.notes, dueDate: current.dueDate,
            isCompleted: completed, completionDate: completed ? Date() : nil, calendarTitle: current.calendarTitle
        )
        remindersByID[reminderID] = reminder
        return reminder
    }

    func deleteReminder(id: String) async throws {
        lastDeletedID = id
        guard remindersByID[id] != nil else {
            throw PIMToolError.notFound(kind: "reminder", id: id)
        }
        remindersByID[id] = nil
    }
}

final class MemoryContactStore: ContactStore, @unchecked Sendable {
    var contactsByID: [String: PIMContact]
    var injectedError: PIMToolError?
    var lastCreateDraft: PIMContactDraft?
    var lastUpdateDraft: PIMContactDraft?
    var lastDeletedID: String?
    private var nextID = 1

    init(contacts: [PIMContact] = []) {
        self.contactsByID = [:]
        for contact in contacts { contactsByID[contact.id] = contact }
    }

    func search(name: String?, email: String?, phone: String?) async throws -> [PIMContact] {
        if let injectedError { throw injectedError }
        // AND the criteria, mirroring the real ContactsPIMStore's
        // NSCompoundPredicate(andPredicateWithSubpredicates:) — the fake the
        // contract tests run against must prove what the real store does, not
        // something easier. (The tool-level guard rejects all-nil calls
        // before they reach the store, so the "no criteria" branch is
        // unreachable in practice; we return empty rather than throw to
        // avoid pretending the contract says otherwise.)
        return contactsByID.values
            .filter { contact in
                if let name {
                    guard contact.name.localizedCaseInsensitiveContains(name) else { return false }
                }
                if let email {
                    guard contact.emails.contains(where: { $0.caseInsensitiveCompare(email) == .orderedSame }) else { return false }
                }
                if let phone {
                    guard contact.phones.contains(where: { $0 == phone }) else { return false }
                }
                return true
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func contact(id: String) async throws -> PIMContact? {
        contactsByID[id]
    }

    func createContact(_ draft: PIMContactDraft) async throws -> PIMContact {
        lastCreateDraft = draft
        let id = "ctc\(nextID)"; nextID += 1
        let contact = PIMContact(
            id: id, name: draft.displayName, givenName: draft.givenName, familyName: draft.familyName,
            organization: draft.organization, jobTitle: draft.jobTitle, emails: draft.emails, phones: draft.phones
        )
        contactsByID[id] = contact
        return contact
    }

    func updateContact(id: String, _ draft: PIMContactDraft) async throws -> PIMContact {
        lastUpdateDraft = draft
        guard let current = contactsByID[id] else {
            throw PIMToolError.notFound(kind: "contact", id: id)
        }
        let contact = PIMContact(
            id: id, name: draft.displayName, givenName: draft.givenName, familyName: draft.familyName,
            organization: draft.organization, jobTitle: draft.jobTitle, emails: draft.emails, phones: draft.phones
        )
        contactsByID[id] = contact
        return contact
    }

    func deleteContact(id: String) async throws {
        lastDeletedID = id
        guard contactsByID[id] != nil else {
            throw PIMToolError.notFound(kind: "contact", id: id)
        }
        contactsByID[id] = nil
    }
}
