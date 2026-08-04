import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-108 — schedule_notification: the agent's real output channel. A local
// notification needs no server, no push certificate, no Info.plist key — only
// the host to have requested authorization once. The hardening (2026-08-03
// review top-up E): length caps on title/body, horizon caps on
// time_interval_seconds/date, and a caller-supplied id for de-dupe — a
// notification loop is the cheapest way for an agent to fill Apple's 64-per-app
// cap in one turn, and the caps fence that without making the contract awkward.

@Generable
public struct ScheduleNotificationArguments: Sendable {
    @Guide(description: "Caller-supplied id — second call with the same id replaces the first, so a runaway loop can dedupe")
    public var id: String?
    @Guide(description: "Notification title (max 100 chars; trimmed)")
    public var title: String
    @Guide(description: "Notification body (max 200 chars; optional)")
    public var body: String?
    @Guide(description: "Delay in seconds (exclusive with date; max 24h = 86400)")
    public var time_interval_seconds: Double?
    @Guide(description: "Fire at this ISO 8601 date/time (exclusive with time_interval_seconds; max 30 days out)")
    public var date: String?

    public init(
        id: String? = nil,
        title: String,
        body: String? = nil,
        time_interval_seconds: Double? = nil,
        date: String? = nil
    ) {
        self.id = id
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
    ("notify me when this is done"). Give either a delay in seconds (max 86400, \
    a day) or an ISO 8601 date (max 30 days out). Title is capped at 100 chars, \
    body at 200. Pass an `id` to dedupe — a second call with the same id replaces \
    the first. Consequential — confirm with the user before calling.
    """

    private let scheduler: any NotificationScheduling
    private let timeZone: TimeZone

    public init(
        scheduler: any NotificationScheduling = UserNotificationCenterScheduler(),
        timeZone: TimeZone = .current
    ) {
        self.scheduler = scheduler
        self.timeZone = timeZone
    }

    public func call(arguments: ScheduleNotificationArguments) async throws -> String {
        guard let trimmedTitle = arguments.title.nilIfEmpty else {
            throw ToolNotificationsError.invalidArguments("title must not be empty.")
        }
        guard trimmedTitle.count <= Self.maxTitleLength else {
            throw ToolNotificationsError.invalidArguments(
                "title is \(trimmedTitle.count) chars; the max is \(Self.maxTitleLength)."
            )
        }
        if let body = arguments.body, let trimmedBody = body.nilIfEmpty {
            guard trimmedBody.count <= Self.maxBodyLength else {
                throw ToolNotificationsError.invalidArguments(
                    "body is \(trimmedBody.count) chars; the max is \(Self.maxBodyLength)."
                )
            }
        }
        let trigger: NotificationTrigger
        let description: String
        switch (arguments.time_interval_seconds, arguments.date) {
        case let (seconds?, _):
            guard seconds > 0 else {
                throw ToolNotificationsError.invalidArguments("time_interval_seconds must be positive.")
            }
            guard seconds <= Self.maxIntervalSeconds else {
                throw ToolNotificationsError.invalidArguments(
                    "time_interval_seconds is \(Int(seconds))s; the horizon is \(Int(Self.maxIntervalSeconds))s (24h)."
                )
            }
            trigger = .timeInterval(seconds)
            description = "in \(Int(seconds.rounded()))s"
        case let (nil, dateString?):
            let date = try parseDate(dateString)
            guard date > Date() else {
                throw ToolNotificationsError.invalidArguments("date must be in the future.")
            }
            let horizon = Date().addingTimeInterval(Self.maxDateHorizonSeconds)
            guard date <= horizon else {
                throw ToolNotificationsError.invalidArguments(
                    "date is \(date.formatted(.iso8601)); the horizon is \(horizon.formatted(.iso8601)) (30 days out)."
                )
            }
            trigger = .date(date)
            description = "at \(date.formatted(.iso8601))"
        case (nil, nil):
            throw ToolNotificationsError.invalidArguments("schedule_notification needs time_interval_seconds or date.")
        }

        // Caller-supplied id lets a loop dedupe — same id on a second call
        // replaces the first (UNNotificationRequest semantics). When absent,
        // mint a fresh id; behavior unchanged for existing callers.
        let id = arguments.id.nilIfEmpty ?? UUID().uuidString
        try await scheduler.requestAuthorization()
        try await scheduler.schedule(
            id: id, title: trimmedTitle,
            body: arguments.body?.nilIfEmpty,
            trigger: trigger
        )
        return "Scheduled \"\(trimmedTitle)\" \(description) [id: \(id)]"
    }

    /// 100 chars is roughly a long notification title; UN truncates silently
    /// past this so the model would get no feedback. The cap is enforced
    /// here so the rejection is named.
    static let maxTitleLength = 100
    /// 200 chars is roughly a 3-line body, again before UN silent truncation.
    static let maxBodyLength = 200
    /// One day — "remind me in an hour" / "notify me when this is done" are
    /// the killer asks; anything scheduled 25+ hours out is a runaway loop.
    static let maxIntervalSeconds: Double = 86_400
    /// 30 days — long enough for "remind me next week" / "remind me on the
    /// trip"; short enough to stop a misread future-date ("2030-01-01" the
    /// model meant "2026-03-01") filling the queue.
    static let maxDateHorizonSeconds: Double = 30 * 86_400

    private func parseDate(_ raw: String) throws -> Date {
        var style = Date.ISO8601FormatStyle()
        style.timeZone = timeZone
        if let date = try? Date(raw, strategy: style) { return date }
        throw ToolNotificationsError.invalidArguments(
            "Couldn't parse '\(raw)' as a date. Use ISO 8601 (2026-08-02T15:00:00Z)."
        )
    }
}
