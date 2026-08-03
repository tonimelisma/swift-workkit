import Foundation

// REQ: ROADMAP item 3 — the model-facing output style for the PIM tools, kept
// consistent with the rest of ToolKit: numbered plain text, no markdown tables,
// count-capped with an honest "[Showing first N of M]" note (the read_file
// paging spirit), and every item carries its stable `[id: …]` handle so the
// update/delete tools can target it.

enum PIMOutput {
    static func list<T>(_ all: [T], limit: Int, line: (T) -> String) -> String {
        guard !all.isEmpty else { return "[No results]" }
        let shown = all.prefix(limit)
        var lines = shown.enumerated().map { "\($0.offset + 1). \(line($0.element))" }
        if all.count > limit {
            lines.append("[Showing first \(limit) of \(all.count). Narrow the query for more.]")
        }
        return lines.joined(separator: "\n")
    }

    static func eventLine(_ event: PIMEvent, calendar: Calendar, timeZone: TimeZone, locale: Locale = .current) -> String {
        let when: String
        if event.isAllDay {
            when = "\(PIMDate.formatDay(event.startDate, timeZone: timeZone, locale: locale)) (all day)"
        } else if calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
            when = "\(PIMDate.formatDay(event.startDate, timeZone: timeZone, locale: locale)) " +
                "\(PIMDate.formatTime(event.startDate, timeZone: timeZone, locale: locale))–\(PIMDate.formatTime(event.endDate, timeZone: timeZone, locale: locale))"
        } else {
            when = "\(PIMDate.format(event.startDate, timeZone: timeZone, locale: locale)) – \(PIMDate.format(event.endDate, timeZone: timeZone, locale: locale))"
        }
        var details = ["Calendar: \(event.calendarTitle)"]
        if let location = event.location, !location.isEmpty { details.append("Location: \(location)") }
        if let notes = event.notes, !notes.isEmpty { details.append("Notes: \(truncate(notes))") }
        let idLine = event.id.map { "[id: \($0)]" } ?? ""
        return "\(when) — \(event.title)\n   \(details.joined(separator: " · "))\n   \(idLine)"
    }

    static func calendarLine(_ calendar: PIMCalendar) -> String {
        let flag = calendar.allowsModification ? "" : " (read-only)"
        return "\(calendar.title)\(flag)\n   [id: \(calendar.id)]"
    }

    static func reminderLine(_ reminder: PIMReminder, timeZone: TimeZone, locale: Locale = .current) -> String {
        var parts: [String] = []
        if let dueDate = reminder.dueDate {
            parts.append("due \(PIMDate.format(dueDate, timeZone: timeZone, locale: locale))")
        } else {
            parts.append("no due date")
        }
        if reminder.isCompleted {
            let completed = reminder.completionDate.map { "completed \(PIMDate.format($0, timeZone: timeZone, locale: locale))" }
                ?? "completed"
            parts.append(completed)
        }
        var body = "\(reminder.title) (\(parts.joined(separator: ", ")))"
        if let notes = reminder.notes, !notes.isEmpty {
            body += "\n   Notes: \(truncate(notes))"
        }
        return "\(body)\n   [id: \(reminder.id)]"
    }

    static func contactLine(_ contact: PIMContact) -> String {
        var details: [String] = []
        if let organization = contact.organization, !organization.isEmpty { details.append(organization) }
        if let jobTitle = contact.jobTitle, !jobTitle.isEmpty { details.append(jobTitle) }
        if !contact.emails.isEmpty { details.append("Emails: \(contact.emails.joined(separator: ", "))") }
        if !contact.phones.isEmpty { details.append("Phones: \(contact.phones.joined(separator: ", "))") }
        var body = contact.name
        if !details.isEmpty { body += " — \(details.joined(separator: " · "))" }
        return "\(body)\n   [id: \(contact.id)]"
    }

    private static func truncate(_ text: String, maximumCharacters: Int = 200) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters)) + "…"
    }
}
