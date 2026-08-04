import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-108 — schedule_notification: the agent's real output channel. A local
// notification needs no server, no push certificate, no Info.plist key — only
// the host to have requested authorization once.

@Generable
public struct ScheduleNotificationArguments: Sendable {
    @Guide(description: "Notification title")
    public var title: String
    @Guide(description: "Notification body")
    public var body: String?
    @Guide(description: "Delay in seconds (exclusive with date)")
    public var time_interval_seconds: Double?
    @Guide(description: "Fire at this ISO 8601 date/time (exclusive with time_interval_seconds)")
    public var date: String?

    public init(title: String, body: String? = nil, time_interval_seconds: Double? = nil, date: String? = nil) {
        self.title = title
        self.body = body
        self.time_interval_seconds = time_interval_seconds
        self.date = date
    }
}

public struct ScheduleNotificationTool: Tool, Sendable {
    public let name = "schedule_notification"
    public let description = """
    Schedule a local notification — the way the agent reaches the user later \
    ("notify me when this is done"). Give either a delay in seconds or an ISO \
    8601 date. Consequential — confirm with the user before calling.
    """

    private let scheduler: any NotificationScheduling
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(
        scheduler: any NotificationScheduling = UserNotificationCenterScheduler(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.scheduler = scheduler
        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func call(arguments: ScheduleNotificationArguments) async throws -> String {
        guard arguments.title.nilIfEmpty != nil else {
            throw ToolNotificationsError.invalidArguments("title must not be empty.")
        }
        let trigger: NotificationTrigger
        let description: String
        switch (arguments.time_interval_seconds, arguments.date) {
        case let (seconds?, _):
            guard seconds > 0 else {
                throw ToolNotificationsError.invalidArguments("time_interval_seconds must be positive.")
            }
            trigger = .timeInterval(seconds)
            description = "in \(Int(seconds.rounded()))s"
        case let (nil, dateString?):
            let date = try parseDate(dateString)
            guard date > Date() else {
                throw ToolNotificationsError.invalidArguments("date must be in the future.")
            }
            trigger = .date(date)
            description = "at \(date.formatted(.iso8601))"
        case (nil, nil):
            throw ToolNotificationsError.invalidArguments("schedule_notification needs time_interval_seconds or date.")
        }

        let id = UUID().uuidString
        try await scheduler.requestAuthorization()
        try await scheduler.schedule(id: id, title: arguments.title, body: arguments.body, trigger: trigger)
        return "Scheduled \"\(arguments.title)\" \(description) [id: \(id)]"
    }

    private func parseDate(_ raw: String) throws -> Date {
        var style = Date.ISO8601FormatStyle()
        style.timeZone = timeZone
        if let date = try? Date(raw, strategy: style) { return date }
        throw ToolNotificationsError.invalidArguments(
            "Couldn't parse '\(raw)' as a date. Use ISO 8601 (2026-08-02T15:00:00Z)."
        )
    }
}
