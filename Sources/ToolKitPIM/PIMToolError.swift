import Foundation

// REQ: ROADMAP item 3 — every PIM error names what the host must fix. A TCC
// denial names the exact Info.plist usage-description key, so a host that
// forgot a key gets told which one — the README promise ("each tool documents
// the Info.plist keys its host app needs") enforced by the error itself.

public enum PIMToolError: LocalizedError, Equatable, Sendable {
    /// The user denied (or the OS restricted) access to a framework. `key` is
    /// the exact usage-description Info.plist key the host must carry.
    case accessDenied(framework: String, usageDescriptionKey: String)
    /// Calendar access was granted write-only; reads require full access.
    case calendarReadOnlyAccess
    /// A referenced item (event/reminder/contact) or calendar no longer exists.
    case notFound(kind: String, id: String)
    /// A calendar title in an argument matched nothing the user owns.
    case calendarNotFound(String)
    /// The tool's arguments were malformed; the message says how to fix them.
    case invalidArguments(String)
    /// A framework call failed; the message is the framework's own, since it is
    /// the ground truth (a permission edge, a sync conflict, an entitlement).
    case storeFailure(String)

    public var errorDescription: String? {
        switch self {
        case let .accessDenied(framework, key):
            "\(framework) access was denied. Add \(key) to the host app's Info.plist and grant access in System Settings."
        case .calendarReadOnlyAccess:
            "Calendar access is write-only, so events can't be read. Add NSCalendarsFullAccessUsageDescription and grant full access in System Settings."
        case let .notFound(kind, id):
            "No \(kind) with id \(id) was found. List items first — the id must come from that output."
        case let .calendarNotFound(title):
            "No calendar named '\(title)'. Use list_calendars to see the available titles."
        case let .invalidArguments(message):
            message
        case let .storeFailure(message):
            "The system store failed: \(message)"
        }
    }
}
