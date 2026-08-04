import Foundation
import Testing
@testable import ToolKitNotifications

// REQ: FR-108 — schedule_notification contract against a fake scheduler. A
// delivered notification needs an authorized host; the offline suite asserts the
// trigger construction and validation.

private final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    var authorizationRequested = false
    var scheduled: [(id: String, title: String, body: String?, trigger: NotificationTrigger)] = []
    var denyAuthorization = false

    func requestAuthorization() async throws {
        if denyAuthorization { throw ToolNotificationsError.authorizationDenied }
        authorizationRequested = true
    }

    func schedule(id: String, title: String, body: String?, trigger: NotificationTrigger) async throws {
        scheduled.append((id, title, body, trigger))
    }
}

@Test("FR-108: a time-interval trigger schedules with the right spec")
func timeIntervalSchedules() async throws {
    let scheduler = FakeNotificationScheduler()
    let tool = ScheduleNotificationTool(scheduler: scheduler)
    let output = try await tool.call(arguments: .init(title: "Done", body: "The build finished", time_interval_seconds: 60))
    #expect(output.hasPrefix("Scheduled \"Done\" in 60s [id: "))
    #expect(scheduler.authorizationRequested)
    guard let entry = scheduler.scheduled.first else {
        Issue.record("nothing scheduled"); return
    }
    #expect(entry.title == "Done")
    #expect(entry.body == "The build finished")
    #expect(entry.trigger == .timeInterval(60))
}

@Test("FR-108: a date trigger is accepted and validated")
func dateTriggerSchedules() async throws {
    let scheduler = FakeNotificationScheduler()
    let tool = ScheduleNotificationTool(scheduler: scheduler)
    let future = Date().addingTimeInterval(3600)
    let iso = future.formatted(.iso8601)
    _ = try await tool.call(arguments: .init(title: "Later", date: iso))
    guard let entry = scheduler.scheduled.first else {
        Issue.record("nothing scheduled"); return
    }
    if case .date(let date) = entry.trigger {
        #expect(abs(date.timeIntervalSince(future)) < 1)
    } else {
        Issue.record("expected a date trigger")
    }
}

@Test("FR-108: an empty title, no trigger, or a past date is rejected")
func validation() async throws {
    let tool = ScheduleNotificationTool(scheduler: FakeNotificationScheduler())
    await #expect(throws: ToolNotificationsError.invalidArguments("title must not be empty.")) {
        _ = try await tool.call(arguments: .init(title: " "))
    }
    await #expect(throws: ToolNotificationsError.invalidArguments("schedule_notification needs time_interval_seconds or date.")) {
        _ = try await tool.call(arguments: .init(title: "X"))
    }
    await #expect(throws: ToolNotificationsError.invalidArguments("time_interval_seconds must be positive.")) {
        _ = try await tool.call(arguments: .init(title: "X", time_interval_seconds: -5))
    }
    await #expect(throws: ToolNotificationsError.invalidArguments("date must be in the future.")) {
        _ = try await tool.call(arguments: .init(title: "X", date: "2000-01-01T00:00:00Z"))
    }
}

@Test("FR-108: a denied authorization propagates named")
func denialPropagates() async throws {
    let scheduler = FakeNotificationScheduler()
    scheduler.denyAuthorization = true
    let tool = ScheduleNotificationTool(scheduler: scheduler)
    await #expect(throws: ToolNotificationsError.authorizationDenied) {
        _ = try await tool.call(arguments: .init(title: "X", time_interval_seconds: 60))
    }
}

// MARK: - 2026-08-03 review top-up E: length/horizon caps, caller-supplied id, title trim

@Test("FR-108: an overlong title is rejected with the count named (review top-up E)")
func overlongTitleRejected() async throws {
    let tool = ScheduleNotificationTool(scheduler: FakeNotificationScheduler())
    let long = String(repeating: "x", count: 101)
    await #expect(throws: ToolNotificationsError.invalidArguments(
        "title is 101 chars; the max is \(ScheduleNotificationTool.maxTitleLength)."
    )) {
        _ = try await tool.call(arguments: .init(title: long, time_interval_seconds: 60))
    }
    // Boundary: 100 chars succeeds.
    let scheduler = FakeNotificationScheduler()
    let tool2 = ScheduleNotificationTool(scheduler: scheduler)
    let exact = String(repeating: "x", count: 100)
    _ = try await tool2.call(arguments: .init(title: exact, time_interval_seconds: 60))
    #expect(scheduler.scheduled.first?.title == exact)
}

@Test("FR-108: an overlong body is rejected (review top-up E)")
func overlongBodyRejected() async throws {
    let tool = ScheduleNotificationTool(scheduler: FakeNotificationScheduler())
    let long = String(repeating: "y", count: 201)
    await #expect(throws: ToolNotificationsError.invalidArguments(
        "body is 201 chars; the max is \(ScheduleNotificationTool.maxBodyLength)."
    )) {
        _ = try await tool.call(arguments: .init(title: "T", body: long, time_interval_seconds: 60))
    }
    // Boundary: 200 chars succeeds.
    let scheduler = FakeNotificationScheduler()
    let tool2 = ScheduleNotificationTool(scheduler: scheduler)
    let exact = String(repeating: "y", count: 200)
    _ = try await tool2.call(arguments: .init(title: "T", body: exact, time_interval_seconds: 60))
    #expect(scheduler.scheduled.first?.body == exact)
}

@Test("FR-108: time_interval_seconds beyond 24h is rejected (review top-up E)")
func intervalHorizonRejected() async throws {
    let tool = ScheduleNotificationTool(scheduler: FakeNotificationScheduler())
    await #expect(throws: ToolNotificationsError.invalidArguments(
        "time_interval_seconds is 172800s; the horizon is \(Int(ScheduleNotificationTool.maxIntervalSeconds))s (24h)."
    )) {
        _ = try await tool.call(arguments: .init(title: "T", time_interval_seconds: 172_800))
    }
    // Boundary: 24h succeeds.
    let scheduler = FakeNotificationScheduler()
    let tool2 = ScheduleNotificationTool(scheduler: scheduler)
    _ = try await tool2.call(arguments: .init(title: "T", time_interval_seconds: 86_400))
    #expect(scheduler.scheduled.first?.trigger == .timeInterval(86_400))
}

@Test("FR-108: a date more than 30 days out is rejected (review top-up E)")
func dateHorizonRejected() async throws {
    let tool = ScheduleNotificationTool(scheduler: FakeNotificationScheduler())
    let far = Date().addingTimeInterval(31 * 86_400).formatted(.iso8601)
    await #expect(throws: ToolNotificationsError.self) {
        _ = try await tool.call(arguments: .init(title: "T", date: far))
    }
    // Boundary: 30 days out succeeds (just under the cap to avoid flakiness).
    let scheduler = FakeNotificationScheduler()
    let tool2 = ScheduleNotificationTool(scheduler: scheduler)
    let near = Date().addingTimeInterval(29 * 86_400).formatted(.iso8601)
    _ = try await tool2.call(arguments: .init(title: "T", date: near))
    #expect(scheduler.scheduled.count == 1)
}

@Test("FR-108: a caller-supplied id is honored for de-dupe (review top-up E)")
func callerSuppliedIdHonored() async throws {
    let scheduler = FakeNotificationScheduler()
    let tool = ScheduleNotificationTool(scheduler: scheduler)
    let output1 = try await tool.call(arguments: .init(id: "restart-123", title: "First", time_interval_seconds: 60))
    #expect(output1.contains("[id: restart-123]"))
    #expect(scheduler.scheduled.first?.id == "restart-123")

    // Second call with the same id replaces the first — UN's documented
    // behavior on `add` with a duplicate identifier. The fake records
    // each call independently (no replacement in the test double), so we
    // just assert the second scheduling carries the same caller-supplied
    // id; the production path inside `UserNotificationCenterScheduler`
    // hands it to `UNNotificationRequest(identifier:)` and UN does the
    // replacement.
    _ = try await tool.call(arguments: .init(id: "restart-123", title: "Second", time_interval_seconds: 120))
    #expect(scheduler.scheduled.last?.id == "restart-123")
    #expect(scheduler.scheduled.last?.title == "Second")
}

@Test("FR-108: title is trimmed before scheduling (review top-up E)")
func titleTrimmed() async throws {
    let scheduler = FakeNotificationScheduler()
    let tool = ScheduleNotificationTool(scheduler: scheduler)
    _ = try await tool.call(arguments: .init(title: "   Padded   ", time_interval_seconds: 60))
    #expect(scheduler.scheduled.first?.title == "Padded")
}
