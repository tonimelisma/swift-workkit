import Foundation
import Testing
@testable import ToolKitPIM

// REQ: FR-091..FR-095 — reminder tool contracts against in-memory doubles.

@Test("FR-091: list_reminders formats state, due dates, and ids")
func listRemindersFormats() async throws {
    let due = try PIMDate.parse("2026-08-03T09:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let store = MemoryReminderStore(reminders: [
        PIMReminder(id: "r1", title: "Invoice", notes: "Q3", dueDate: due, isCompleted: false, completionDate: nil, calendarTitle: "Reminders"),
        PIMReminder(id: "r2", title: "No date", notes: nil, dueDate: nil, isCompleted: true, completionDate: due, calendarTitle: "Reminders"),
    ])
    let tool = ListRemindersTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    let output = normalized(try await tool.call(arguments: .init(state: "all")))
    #expect(output.contains("1. Invoice (due Aug 3, 2026 at 9:00 AM)"))
    #expect(output.contains("[id: r1]"))
    #expect(output.contains("2. No date (no due date, completed Aug 3, 2026 at 9:00 AM)"))
}

@Test("FR-091: list_reminders defaults to incomplete and sorts undated last")
func listRemindersDefaultsToIncomplete() async throws {
    let due = try PIMDate.parse("2026-08-03T09:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let store = MemoryReminderStore(reminders: [
        PIMReminder(id: "r1", title: "Open", notes: nil, dueDate: due, isCompleted: false, completionDate: nil, calendarTitle: "Reminders"),
        PIMReminder(id: "r2", title: "Done", notes: nil, dueDate: nil, isCompleted: true, completionDate: due, calendarTitle: "Reminders"),
    ])
    let tool = ListRemindersTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    let output = try await tool.call(arguments: .init())
    #expect(output.contains("Open"))
    #expect(!output.contains("Done"))
}

@Test("FR-091: list_reminders validates state and due range")
func listRemindersValidates() async throws {
    let tool = ListRemindersTool(store: MemoryReminderStore(), calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    await #expect(throws: PIMToolError.invalidArguments("state must be 'incomplete', 'completed', or 'all'; got 'maybe'.")) {
        _ = try await tool.call(arguments: .init(state: "maybe"))
    }
    await #expect(throws: PIMToolError.invalidArguments("due_to must be after due_from.")) {
        _ = try await tool.call(arguments: .init(due_from: "2026-08-05", due_to: "2026-08-04"))
    }
}

@Test("FR-092: add_reminder builds the draft and reports the id")
func addReminderBuildsDraft() async throws {
    let store = MemoryReminderStore(lists: [PIMCalendar(id: "rl-1", title: "Errands", allowsModification: true)])
    let tool = AddReminderTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone)
    let due = try PIMDate.parse("2026-08-04T18:00:00Z", calendar: fixedCalendar, timeZone: fixedTimeZone)
    let output = try await tool.call(arguments: .init(title: "Milk", due: "2026-08-04T18:00:00Z", list: "Errands"))
    #expect(output == "Added \"Milk\" [id: rmd1]")
    #expect(store.lastCreateDraft?.title == "Milk")
    #expect(store.lastCreateDraft?.dueDate == due)
    #expect(store.lastCreateDraft?.calendarTitle == "Errands")
}

@Test("FR-092: add_reminder rejects an empty title")
func addReminderRejectsEmptyTitle() async throws {
    let tool = AddReminderTool(store: MemoryReminderStore(), calendar: fixedCalendar, timeZone: fixedTimeZone)
    await #expect(throws: PIMToolError.invalidArguments("title must not be empty.")) {
        _ = try await tool.call(arguments: .init(title: " "))
    }
}

@Test("FR-093: complete_reminder completes once and is idempotent")
func completeReminderIdempotent() async throws {
    let store = MemoryReminderStore(reminders: [
        PIMReminder(id: "r1", title: "Open", notes: nil, dueDate: nil, isCompleted: false, completionDate: nil, calendarTitle: "Reminders"),
    ])
    let tool = CompleteReminderTool(store: store)
    let first = try await tool.call(arguments: .init(id: "r1"))
    #expect(first == "Completed \"Open\"")
    #expect(store.lastToggled?.completed == true)
    let second = try await tool.call(arguments: .init(id: "r1"))
    #expect(second == "\"Open\" was already completed.")
}

@Test("FR-094: uncomplete_reminder re-opens a completed reminder")
func uncompleteReminderReopens() async throws {
    let store = MemoryReminderStore(reminders: [
        PIMReminder(id: "r1", title: "Done", notes: nil, dueDate: nil, isCompleted: true, completionDate: Date(), calendarTitle: "Reminders"),
    ])
    let tool = UncompleteReminderTool(store: store)
    let first = try await tool.call(arguments: .init(id: "r1"))
    #expect(first == "Reopened \"Done\"")
    #expect(store.lastToggled?.completed == false)
    let second = try await tool.call(arguments: .init(id: "r1"))
    #expect(second == "\"Done\" was already open.")
}

@Test("FR-093/FR-094/FR-095: reminder write tools report a missing id")
func reminderWritesReportMissing() async throws {
    let store = MemoryReminderStore()
    let complete = CompleteReminderTool(store: store)
    await #expect(throws: PIMToolError.notFound(kind: "reminder", id: "gone")) {
        _ = try await complete.call(arguments: .init(id: "gone"))
    }
    let uncomplete = UncompleteReminderTool(store: store)
    await #expect(throws: PIMToolError.notFound(kind: "reminder", id: "gone")) {
        _ = try await uncomplete.call(arguments: .init(id: "gone"))
    }
    let delete = DeleteReminderTool(store: store)
    await #expect(throws: PIMToolError.notFound(kind: "reminder", id: "gone")) {
        _ = try await delete.call(arguments: .init(id: "gone"))
    }
}

@Test("FR-095: delete_reminder confirms by title")
func deleteReminderConfirms() async throws {
    let store = MemoryReminderStore(reminders: [
        PIMReminder(id: "r1", title: "Doomed", notes: nil, dueDate: nil, isCompleted: false, completionDate: nil, calendarTitle: "Reminders"),
    ])
    let tool = DeleteReminderTool(store: store)
    let output = try await tool.call(arguments: .init(id: "r1"))
    #expect(output == "Deleted \"Doomed\"")
    #expect(store.lastDeletedID == "r1")
}

@Test("FR-091: an access denial from the store propagates named")
func reminderReadAccessDenialPropagates() async throws {
    let store = MemoryReminderStore()
    store.injectedError = PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSRemindersFullAccessUsageDescription")
    let tool = ListRemindersTool(store: store, calendar: fixedCalendar, timeZone: fixedTimeZone, locale: fixedLocale)
    await #expect(throws: PIMToolError.accessDenied(framework: "EventKit", usageDescriptionKey: "NSRemindersFullAccessUsageDescription")) {
        _ = try await tool.call(arguments: .init())
    }
}
