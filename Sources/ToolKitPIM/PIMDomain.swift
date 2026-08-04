import Foundation

// REQ: ROADMAP item 3 — ToolKitPIM owns the cross-platform schemas for the PIM
// domains (Contacts, Calendar, Reminders). EventKit and Contacts exist on both
// macOS 27 and iOS 27 (verified 2026-08-02), so one domain target serves both
// platforms. The schemas are plain values, not `@Generable` argument types —
// the model-facing schemas live on each tool's argument struct and convert
// into these drafts.

/// One calendar (or reminder list) the user can target with the write tools.
public struct PIMCalendar: Sendable, Equatable {
    public var id: String
    public var title: String
    public var allowsModification: Bool

    public init(id: String, title: String, allowsModification: Bool) {
        self.id = id
        self.title = title
        self.allowsModification = allowsModification
    }
}

/// A calendar event, as read from the store. `id` is `EKEvent.eventIdentifier` —
/// stable across edits, so the update/delete tools can target it.
public struct PIMEvent: Sendable, Equatable {
    public var id: String?
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var calendarTitle: String

    public init(
        id: String?,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        calendarTitle: String
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarTitle = calendarTitle
    }
}

/// What `create_calendar_event` / `update_calendar_event` hand the store.
/// `calendarTitle` is nil on create to mean "default writable calendar"; on
/// update the tool overlays it from the current event so the calendar only
/// changes when the patch says so.
public struct PIMEventDraft: Sendable, Equatable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var calendarTitle: String?

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String?,
        notes: String?,
        calendarTitle: String?
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarTitle = calendarTitle
    }
}

/// A reminder, as read from the store. `id` is `EKCalendarItem.calendarItemIdentifier`.
public struct PIMReminder: Sendable, Equatable {
    public var id: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var isCompleted: Bool
    public var completionDate: Date?
    public var calendarTitle: String

    public init(
        id: String,
        title: String,
        notes: String?,
        dueDate: Date?,
        isCompleted: Bool,
        completionDate: Date?,
        calendarTitle: String
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.calendarTitle = calendarTitle
    }
}

/// What `add_reminder` hands the store.
public struct PIMReminderDraft: Sendable, Equatable {
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var calendarTitle: String?

    public init(title: String, notes: String?, dueDate: Date?, calendarTitle: String?) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.calendarTitle = calendarTitle
    }
}

/// A contact, as read from the store. `id` is `CNContact.identifier`. `name` is
/// the display name (given + family, else organization) the tools format with.
public struct PIMContact: Sendable, Equatable {
    public var id: String
    public var name: String
    public var givenName: String
    public var familyName: String
    public var organization: String?
    public var jobTitle: String?
    public var emails: [String]
    public var phones: [String]

    public init(
        id: String,
        name: String,
        givenName: String,
        familyName: String,
        organization: String?,
        jobTitle: String?,
        emails: [String],
        phones: [String]
    ) {
        self.id = id
        self.name = name
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.jobTitle = jobTitle
        self.emails = emails
        self.phones = phones
    }
}

/// What the contact write tools hand the store. Empty strings mean "no value";
/// the store maps them onto the framework's empty-state (an empty CNMutableContact
/// property) rather than nil, since Contacts has no clear/delete field concept.
public struct PIMContactDraft: Sendable, Equatable {
    public var givenName: String
    public var familyName: String
    public var organization: String?
    public var jobTitle: String?
    public var emails: [String]
    public var phones: [String]

    public init(
        givenName: String,
        familyName: String,
        organization: String?,
        jobTitle: String?,
        emails: [String],
        phones: [String]
    ) {
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.jobTitle = jobTitle
        self.emails = emails
        self.phones = phones
    }

    public var displayName: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (organization?.isEmpty == false ? organization! : "Unnamed") : name
    }

    public var hasAnyValue: Bool {
        !givenName.isEmpty || !familyName.isEmpty || organization?.isEmpty == false
    }
}
