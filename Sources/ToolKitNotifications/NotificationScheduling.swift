import Foundation
import UserNotifications

// REQ: FR-108 — the scheduling seam. Tools depend on it, never on
// UNUserNotificationCenter directly, so scheduling is testable offline (a
// delivered notification needs an authorized host).

/// When a scheduled notification should fire.
public enum NotificationTrigger: Sendable, Equatable {
    case timeInterval(TimeInterval)
    case date(Date)
}

public protocol NotificationScheduling: Sendable {
    /// Requests alert/sound authorization; throws named if denied.
    func requestAuthorization() async throws
    /// Schedules (or replaces, by id) a notification.
    func schedule(id: String, title: String, body: String?, trigger: NotificationTrigger) async throws
}

public enum ToolNotificationsError: LocalizedError, Equatable, Sendable {
    case authorizationDenied
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Notifications are not authorized. The host must request authorization (UNUserNotificationCenter) and the user must grant it in System Settings."
        case let .invalidArguments(message):
            message
        }
    }
}

/// UNUserNotificationCenter is documented thread-safe; the scheduler is
/// stateless beyond that shared instance.
public struct UserNotificationCenterScheduler: NotificationScheduling, @unchecked Sendable {
    public init() {}

    public func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw ToolNotificationsError.authorizationDenied }
    }

    public func schedule(id: String, title: String, body: String?, trigger: NotificationTrigger) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body, !body.isEmpty { content.body = body }

        let unTrigger: UNNotificationTrigger
        switch trigger {
        case let .timeInterval(seconds):
            unTrigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        case let .date(date):
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            unTrigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: unTrigger)
        try await UNUserNotificationCenter.current().add(request)
    }
}
