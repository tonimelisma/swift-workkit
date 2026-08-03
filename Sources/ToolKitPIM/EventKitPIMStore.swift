import EventKit
import Foundation

// REQ: ROADMAP item 3 — the EventKit-backed implementation of both calendar
// and reminders. One EKEventStore serves both, since the framework models them
// as one store. @unchecked Sendable is a deliberate, documented call: EKEventStore
// is thread-safe per Apple's documentation, and the tool protocol requires
// Sendable. All reads/writes run through the authorization ladder so a host
// missing a usage-description key gets told exactly which one.

public final class EventKitPIMStore: CalendarEventStore, ReminderStore, @unchecked Sendable {
    private let store = EKEventStore()

    public init() {}

    // MARK: - Authorization

    private func ensureEventReadAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            return
        case .writeOnly:
            throw PIMToolError.calendarReadOnlyAccess
        case .notDetermined:
            guard try await store.requestFullAccessToEvents() else {
                throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")
            }
        case .denied, .restricted:
            throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")
        @unknown default:
            throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")
        }
    }

    private func ensureEventWriteAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess, .writeOnly:
            return
        case .notDetermined:
            guard try await store.requestFullAccessToEvents() else {
                throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")
            }
        case .denied, .restricted:
            throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")
        @unknown default:
            throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")
        }
    }

    private func ensureReminderAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .authorized, .fullAccess:
            return
        case .notDetermined:
            guard try await store.requestFullAccessToReminders() else {
                throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSRemindersFullAccessUsageDescription")
            }
        case .denied, .restricted, .writeOnly:
            throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSRemindersFullAccessUsageDescription")
        @unknown default:
            throw PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSRemindersFullAccessUsageDescription")
        }
    }

    // MARK: - Calendars

    private func eventCalendar(_ title: String) throws -> EKCalendar {
        let match = store.calendars(for: .event).first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
        guard let match else { throw PIMToolError.calendarNotFound(title) }
        return match
    }

    private func reminderCalendar(_ title: String) throws -> EKCalendar {
        let match = store.calendars(for: .reminder).first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
        guard let match else { throw PIMToolError.calendarNotFound(title) }
        return match
    }

    private func defaultEventCalendar() throws -> EKCalendar {
        let calendars = store.calendars(for: .event)
        guard let first = calendars.first(where: { $0.allowsContentModifications }) ?? calendars.first else {
            throw PIMToolError.invalidArguments("No event calendar is available to write to.")
        }
        return first
    }

    private func defaultReminderCalendar() throws -> EKCalendar {
        let calendars = store.calendars(for: .reminder)
        guard let first = calendars.first(where: { $0.allowsContentModifications }) ?? calendars.first else {
            throw PIMToolError.invalidArguments("No reminder list is available to write to.")
        }
        return first
    }

    private func calendars(matching titles: [String]?, entity: EKEntityType) throws -> [EKCalendar] {
        let all = store.calendars(for: entity)
        guard let titles else { return all }
        return all.filter { calendar in titles.contains { $0.caseInsensitiveCompare(calendar.title) == .orderedSame } }
    }

    // MARK: - CalendarEventStore

    public func calendars() async throws -> [PIMCalendar] {
        try await ensureEventReadAccess()
        return store.calendars(for: .event).map {
            PIMCalendar(id: $0.calendarIdentifier, title: $0.title, allowsModification: $0.allowsContentModifications)
        }
    }

    public func events(from start: Date, to end: Date, calendarTitles: [String]?) async throws -> [PIMEvent] {
        try await ensureEventReadAccess()
        let calendars = try calendars(matching: calendarTitles, entity: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .map(pimEvent(from:))
            .sorted { $0.startDate < $1.startDate }
    }

    public func event(id: String) async throws -> PIMEvent? {
        try await ensureEventReadAccess()
        return store.event(withIdentifier: id).map(pimEvent(from:))
    }

    public func createEvent(_ draft: PIMEventDraft) async throws -> PIMEvent {
        try await ensureEventWriteAccess()
        let calendar = try draft.calendarTitle.map(eventCalendar(_:)) ?? defaultEventCalendar()
        guard calendar.allowsContentModifications else {
            throw PIMToolError.invalidArguments("Calendar '\(calendar.title)' is read-only.")
        }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        if let location = draft.location { event.location = location }
        if let notes = draft.notes { event.notes = notes }
        event.calendar = calendar
        try store.save(event, span: .thisEvent, commit: true)
        return pimEvent(from: event)
    }

    public func updateEvent(id: String, _ draft: PIMEventDraft) async throws -> PIMEvent {
        try await ensureEventWriteAccess()
        guard let event = store.event(withIdentifier: id) else {
            throw PIMToolError.notFound(kind: "calendar event", id: id)
        }
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        if let location = draft.location { event.location = location }
        if let notes = draft.notes { event.notes = notes }
        if let calendarTitle = draft.calendarTitle {
            event.calendar = try eventCalendar(calendarTitle)
        }
        try store.save(event, span: .thisEvent, commit: true)
        return pimEvent(from: event)
    }

    public func deleteEvent(id: String) async throws {
        try await ensureEventWriteAccess()
        guard let event = store.event(withIdentifier: id) else {
            throw PIMToolError.notFound(kind: "calendar event", id: id)
        }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private func pimEvent(from event: EKEvent) -> PIMEvent {
        let start = event.startDate ?? Date()
        let end = event.endDate ?? start
        return PIMEvent(
            id: event.eventIdentifier,
            title: event.title,
            startDate: start,
            endDate: end,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            calendarTitle: event.calendar?.title ?? ""
        )
    }

    // MARK: - ReminderStore

    public func calendarLists() async throws -> [PIMCalendar] {
        try await ensureReminderAccess()
        return store.calendars(for: .reminder).map {
            PIMCalendar(id: $0.calendarIdentifier, title: $0.title, allowsModification: $0.allowsContentModifications)
        }
    }

    public func reminders(
        state: ReminderFilterState,
        dueFrom: Date?,
        dueTo: Date?,
        calendarTitles: [String]?
    ) async throws -> [PIMReminder] {
        try await ensureReminderAccess()
        let calendars = try calendars(matching: calendarTitles, entity: .reminder)
        let predicate: NSPredicate
        switch state {
        case .all:
            predicate = store.predicateForReminders(in: calendars)
        case .incomplete:
            predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        case .completed:
            predicate = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars)
        }
        // fetchReminders(matching:completion:) returns a cancellation token, so
        // it doesn't get the ObjC completion-to-async import; wrap it by hand.
        // Mapping happens inside the continuation because [EKReminder] isn't
        // Sendable and the resume crosses a region boundary.
        let reminders: [PIMReminder] = await withCheckedContinuation { continuation in
            _ = store.fetchReminders(matching: predicate) { fetched in
                continuation.resume(returning: (fetched ?? []).map { self.pimReminder(from: $0) })
            }
        }
        return reminders
            .filter { state == .all || $0.isCompleted == (state == .completed) }
            .filter { reminder in
                guard let dueDate = reminder.dueDate else { return true }
                if let dueFrom, dueDate < dueFrom { return false }
                if let dueTo, dueDate >= dueTo { return false }
                return true
            }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l < r
                case (nil, nil): return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            }
    }

    public func reminder(id: String) async throws -> PIMReminder? {
        try await ensureReminderAccess()
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
        return pimReminder(from: item)
    }

    public func createReminder(_ draft: PIMReminderDraft) async throws -> PIMReminder {
        try await ensureReminderAccess()
        let calendar = try draft.calendarTitle.map(reminderCalendar(_:)) ?? defaultReminderCalendar()
        guard calendar.allowsContentModifications else {
            throw PIMToolError.invalidArguments("Reminder list '\(calendar.title)' is read-only.")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        if let notes = draft.notes { reminder.notes = notes }
        if let dueDate = draft.dueDate {
            reminder.dueDateComponents = components(from: dueDate)
        }
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
        return pimReminder(from: reminder)
    }

    public func setCompleted(_ completed: Bool, reminderID: String) async throws -> PIMReminder {
        try await ensureReminderAccess()
        guard let item = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw PIMToolError.notFound(kind: "reminder", id: reminderID)
        }
        item.isCompleted = completed
        item.completionDate = completed ? Date() : nil
        try store.save(item, commit: true)
        return pimReminder(from: item)
    }

    public func deleteReminder(id: String) async throws {
        try await ensureReminderAccess()
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw PIMToolError.notFound(kind: "reminder", id: id)
        }
        try store.remove(item, commit: true)
    }

    private func pimReminder(from reminder: EKReminder) -> PIMReminder {
        PIMReminder(
            id: reminder.calendarItemIdentifier,
            title: reminder.title,
            notes: reminder.notes,
            dueDate: dueDate(of: reminder),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            calendarTitle: reminder.calendar?.title ?? ""
        )
    }

    private func dueDate(of reminder: EKReminder) -> Date? {
        let calendar = Calendar.current
        guard let components = reminder.dueDateComponents, components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    private func components(from date: Date) -> DateComponents {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        return calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: date)
    }
}
