import Foundation

// REQ: ROADMAP item 3 — the reminders seam (EventKit again; see
// CalendarEventStore.swift for why a seam). `ReminderFilterState` names the
// `list_reminders` states the store must honor; the store resolves due-date and
// state filtering itself so tool semantics are defined here, not by whatever
// EventKit predicate happens to be convenient.

public enum ReminderFilterState: String, Sendable, Equatable {
    case incomplete
    case completed
    case all
}

public protocol ReminderStore: Sendable {
    /// The user's reminder lists. (Named `calendarLists` because EventKit models
    /// reminder lists as calendars and the same type conforms to both store
    /// protocols — a shared `calendars()` name would collide.)
    func calendarLists() async throws -> [PIMCalendar]
    /// Reminders in `state`, sorted by due date (undated last). `dueFrom`/`dueTo`
    /// bound the due date; a non-nil `calendarTitles` filters by reminder-list title.
    func reminders(state: ReminderFilterState, dueFrom: Date?, dueTo: Date?, calendarTitles: [String]?) async throws -> [PIMReminder]
    /// One reminder by stable id, or nil.
    func reminder(id: String) async throws -> PIMReminder?
    /// Creates a reminder; `draft.calendarTitle` nil means "first writable list".
    func createReminder(_ draft: PIMReminderDraft) async throws -> PIMReminder
    /// Marks a reminder completed (`true`) or re-opens it (`false`).
    func setCompleted(_ completed: Bool, reminderID: String) async throws -> PIMReminder
    /// Deletes the reminder `id`.
    func deleteReminder(id: String) async throws
}
