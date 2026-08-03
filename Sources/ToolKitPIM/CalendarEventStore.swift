import Foundation

// REQ: ROADMAP item 3 — the calendar-event seam. Tools depend on this protocol,
// never on EventKit directly, so the whole suite runs offline against fakes: a
// TCC prompt cannot be automated, and the package's testing discipline is
// deterministic (see ENGINEERING.md). The concrete EventKit-backed store lives
// in EventKitPIMStore.swift.

public protocol CalendarEventStore: Sendable {
    /// The user's event calendars.
    func calendars() async throws -> [PIMCalendar]
    /// Events whose start falls in `from..<to`, sorted by start date. A
    /// non-nil `calendarTitles` filters by title (the model-facing handle).
    func events(from: Date, to: Date, calendarTitles: [String]?) async throws -> [PIMEvent]
    /// One event by stable id, or nil. Update tools read-before-write with it.
    func event(id: String) async throws -> PIMEvent?
    /// Creates an event; `draft.calendarTitle` nil means "first writable calendar".
    func createEvent(_ draft: PIMEventDraft) async throws -> PIMEvent
    /// Replaces every field of the event `id` with the draft (the tool overlays
    /// patches onto the current event before calling).
    func updateEvent(id: String, _ draft: PIMEventDraft) async throws -> PIMEvent
    /// Deletes the event `id`.
    func deleteEvent(id: String) async throws
}
