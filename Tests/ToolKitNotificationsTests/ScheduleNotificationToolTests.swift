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
