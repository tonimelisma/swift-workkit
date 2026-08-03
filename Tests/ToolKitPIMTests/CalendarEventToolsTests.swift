import Foundation
import Testing
@testable import ToolKitPIM

// REQ: FR-086..FR-090 — calendar tool contracts, asserted against in-memory
// store doubles. Date formatting is pinned to en_US_POSIX/GMT so assertions are
// machine-independent; structural bits (titles, ids, calendar names) are exact.

@Test("FR-086: list_calendars formats titles, read-only flags, and ids")
func listCalendarsFormats() async throws {
    let store = MemoryCalendarStore(calendarsList: [
        PIMCalendar(id: "cal-1", title: "Work", allowsModification: true),
        PIMCalendar(id: "cal-2", title: "Holidays", allowsModification: false),
    ])
    let tool = ListCalendarsTool(eventStore: store, reminderStore: MemoryReminderStore())
    let output = try await tool.call(arguments: .init())
    #expect(output.contains("1. Work"))
    #expect(output.contains("[id: cal-1]"))
    #expect(output.contains("2. Holidays (read-only)"))
}

@Test("FR-086: list_calendars reminder entity reads reminder lists")
func listCalendarsReminderEntity() async throws {
    let reminderStore = MemoryReminderStore(lists: [PIMCalendar(id: "rl-1", title: "Errands", allowsModification: true)])
    let tool = ListCalendarsTool(eventStore: MemoryCalendarStore(), reminderStore: reminderStore)
    let output = try await tool.call(arguments: .init(entity: "reminder"))
    #expect(output.contains("Errands"))
    #expect(output.contains("[id: rl-1]"))
}

@Test("FR-086: list_calendars rejects an unknown entity")
func listCalendarsRejectsEntity() async throws {
    let tool = ListCalendarsTool(eventStore: MemoryCalendarStore(), reminderStore: MemoryReminderStore())
    await #expect(throws: PIMToolError.invalidArguments("entity must be 'event' or 'reminder'; got 'contacts'.")) {
        _ = try await tool.call(arguments: .init(entity: "contacts"))
    }
}

@Test("FR-087: list_calendar_events returns events in range, sorted, with ids")
func listEventsReturnsSortedInRange() async throws {
    let morning = try PIMDate.parse("2026-08-02T09:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let afternoon = try PIMDate.parse("2026-08-02T15:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let tomorrow = try PIMDate.parse("2026-08-03T10:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let store = MemoryCalendarStore(events: [
        PIMEvent(id: "e1", title: "Standup", startDate: morning, endDate: morning.addingTimeInterval(3600), isAllDay: false, location: nil, notes: nil, calendarTitle: "Work"),
        PIMEvent(id: "e2", title: "Review", startDate: afternoon, endDate: afternoon.addingTimeInterval(3600), isAllDay: false, location: "Room 3", notes: "Iterations 1-2", calendarTitle: "Work"),
        PIMEvent(id: "e3", title: "Tomorrow", startDate: tomorrow, endDate: tomorrow.addingTimeInterval(3600), isAllDay: false, location: nil, notes: nil, calendarTitle: "Work"),
    ])
    let tool = ListCalendarEventsTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    let raw = try await tool.call(arguments: .init(start: "2026-08-02", end: "2026-08-03"))
    let output = normalized(raw)
    #expect(output.contains("1. Aug 2, 2026 9:00 AM–10:00 AM — Standup"))
    #expect(output.contains("2. Aug 2, 2026 3:00 PM–4:00 PM — Review"))
    #expect(!output.contains("Tomorrow"))
    #expect(output.contains("Location: Room 3"))
    #expect(output.contains("Notes: Iterations 1-2"))
    #expect(output.contains("[id: e2]"))
}

@Test("FR-087: list_calendar_events rejects end before start")
func listEventsRejectsInvertedRange() async throws {
    let tool = ListCalendarEventsTool(store: MemoryCalendarStore(), calendar: fixedCalendar, timeZone: fixedTimeZone)
    await #expect(throws: PIMToolError.invalidArguments("end must be after start.")) {
        _ = try await tool.call(arguments: .init(start: "2026-08-03", end: "2026-08-02"))
    }
}

@Test("FR-087: list_calendar_events filters by calendar titles")
func listEventsFiltersByTitles() async throws {
    let day = try PIMDate.parse("2026-08-02T09:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let store = MemoryCalendarStore(events: [
        PIMEvent(id: "e1", title: "Work event", startDate: day, endDate: day.addingTimeInterval(3600), isAllDay: false, location: nil, notes: nil, calendarTitle: "Work"),
        PIMEvent(id: "e2", title: "Home event", startDate: day, endDate: day.addingTimeInterval(3600), isAllDay: false, location: nil, notes: nil, calendarTitle: "Home"),
    ])
    let tool = ListCalendarEventsTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    let output = try await tool.call(arguments: .init(start: "2026-08-02", end: "2026-08-03", calendars: ["Work"]))
    #expect(output.contains("Work event"))
    #expect(!output.contains("Home event"))
}

@Test("FR-087: list_calendar_events caps output with a continue note")
func listEventsCapsOutput() async throws {
    let day = try PIMDate.parse("2026-08-02T09:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let events = (1 ... 5).map { i in
        PIMEvent(id: "e\(i)", title: "Event \(i)", startDate: day.addingTimeInterval(TimeInterval(i) * 60), endDate: day.addingTimeInterval(TimeInterval(i) * 60 + 60), isAllDay: false, location: nil, notes: nil, calendarTitle: "Work")
    }
    let tool = ListCalendarEventsTool(store: MemoryCalendarStore(events: events), calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    let output = try await tool.call(arguments: .init(start: "2026-08-02", end: "2026-08-03", limit: 2))
    #expect(output.contains("Showing first 2 of 5"))
}

@Test("FR-088: create_calendar_event validates range and builds the draft")
func createEventValidatesAndBuildsDraft() async throws {
    let store = MemoryCalendarStore(calendarsList: [PIMCalendar(id: "cal-1", title: "Work", allowsModification: true)])
    let tool = CreateCalendarEventTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    let output = try await tool.call(arguments: .init(title: "Ship", start: "2026-08-05T10:00:00Z", end: "2026-08-05T11:00:00Z", location: "Studio", calendar: "Work"))
    #expect(output.hasPrefix("Created \"Ship\""))
    #expect(output.contains("on Work"))
    #expect(output.contains("[id: evt1]"))
    #expect(store.lastCreateDraft?.title == "Ship")
    #expect(store.lastCreateDraft?.calendarTitle == "Work")
    #expect(store.lastCreateDraft?.location == "Studio")
    #expect(store.lastCreateDraft?.isAllDay == false)
}

@Test("FR-088: create_calendar_event rejects inverted or empty input")
func createEventRejectsBadInput() async throws {
    let store = MemoryCalendarStore()
    let tool = CreateCalendarEventTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    await #expect(throws: PIMToolError.invalidArguments("end must be after start.")) {
        _ = try await tool.call(arguments: .init(title: "Ship", start: "2026-08-05T11:00:00Z", end: "2026-08-05T10:00:00Z"))
    }
    await #expect(throws: PIMToolError.invalidArguments("title must not be empty.")) {
        _ = try await tool.call(arguments: .init(title: "   ", start: "2026-08-05T10:00:00Z", end: "2026-08-05T11:00:00Z"))
    }
}

@Test("FR-089: update_calendar_event rejects an empty patch")
func updateEventRejectsEmptyPatch() async throws {
    let store = MemoryCalendarStore()
    let tool = UpdateCalendarEventTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone)
    await #expect(throws: PIMToolError.invalidArguments("At least one field to update is required.")) {
        _ = try await tool.call(arguments: .init(id: "e1"))
    }
}

@Test("FR-089: update_calendar_event overlays patches on the current event")
func updateEventOverlaysPatches() async throws {
    let morning = try PIMDate.parse("2026-08-02T09:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let store = MemoryCalendarStore(events: [
        PIMEvent(id: "e1", title: "Old title", startDate: morning, endDate: morning.addingTimeInterval(3600), isAllDay: false, location: "Old room", notes: nil, calendarTitle: "Work"),
    ])
    let tool = UpdateCalendarEventTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone)
    let output = try await tool.call(arguments: .init(id: "e1", title: "New title", location: "New room"))
    #expect(output.contains("Updated \"New title\""))
    #expect(output.contains("[id: e1]"))
    #expect(store.lastUpdateDraft?.title == "New title")
    #expect(store.lastUpdateDraft?.location == "New room")
    #expect(store.lastUpdateDraft?.startDate == morning)
}

@Test("FR-089/FR-090: update and delete report a missing id")
func updateAndDeleteReportMissing() async throws {
    let store = MemoryCalendarStore()
    let updateTool = UpdateCalendarEventTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone)
    await #expect(throws: PIMToolError.notFound(kind: "calendar event", id: "nope")) {
        _ = try await updateTool.call(arguments: .init(id: "nope", title: "X"))
    }
    let deleteTool = DeleteCalendarEventTool(store: store)
    await #expect(throws: PIMToolError.notFound(kind: "calendar event", id: "nope")) {
        _ = try await deleteTool.call(arguments: .init(id: "nope"))
    }
}

@Test("FR-090: delete_calendar_event confirms by title")
func deleteEventConfirms() async throws {
    let day = try PIMDate.parse("2026-08-02T09:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let store = MemoryCalendarStore(events: [
        PIMEvent(id: "e1", title: "Doomed", startDate: day, endDate: day.addingTimeInterval(3600), isAllDay: false, location: nil, notes: nil, calendarTitle: "Work"),
    ])
    let tool = DeleteCalendarEventTool(store: store)
    let output = try await tool.call(arguments: .init(id: "e1"))
    #expect(output == "Deleted \"Doomed\"")
    #expect(store.lastDeletedID == "e1")
}

@Test("FR-087: an access denial from the store propagates named")
func calendarReadAccessDenialPropagates() async throws {
    let store = MemoryCalendarStore(calendarsList: [])
    store.injectedError = PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")
    let tool = ListCalendarEventsTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    await #expect(throws: PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSCalendarsFullAccessUsageDescription")) {
        _ = try await tool.call(arguments: .init(start: "2026-08-02", end: "2026-08-03"))
    }
}
