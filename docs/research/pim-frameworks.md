# PIM frameworks on OS 27 (EventKit + Contacts)

What we verified against the macOS 27 and iPhoneOS 27 SDKs on 2026-08-02 before
building ToolKitPIM (ROADMAP item 3). The whole plan rested on these; nobody
should re-verify them to re-derive the shape.

## API parity: one target serves both platforms

Every EventKit and Contacts call ToolKitPIM makes exists identically on macOS 27
and iOS 27 — checked against both SDKs' headers, not assumed:

- `EKEventStore`: `requestFullAccessToEvents`, `requestWriteOnlyAccessToEvents`,
  `requestFullAccessToReminders` (all macOS 14+/iOS 17+), `authorizationStatus(for:)`,
  `event(withIdentifier:)`, `calendarItem(withIdentifier:)`, `calendar(withIdentifier:)`,
  `save`/`remove` for events and reminders, `events(matching:)`,
  `fetchReminders(matching:completion:)`, `calendars(for:)`, and the predicates
  (`predicateForEvents(withStart:end:calendars:)`,
  `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)`,
  `predicateForCompletedReminders(withCompletionDateStarting:ending:calendars:)`,
  `predicateForReminders(in:)`).
- `CNContactStore`: `requestAccess(for: .contacts)`, `authorizationStatus(for: .contacts)`,
  `unifiedContacts(matching:keysToFetch:)`, `unifiedContact(withIdentifier:keysToFetch:)`,
  `execute(_:)` with `CNSaveRequest` (`add`/`update`/`deleteContact`),
  `defaultContainerIdentifier()`, and the predicates
  (`predicateForContacts(matchingName:)`, `(matchingEmailAddress:)`, `(matchingPhoneNumber:)`).

So ToolKitPIM is a single cross-platform domain target, no platform split; the
existing dual-platform `xcodebuild` check proves NFR-010 once the target is added.

## `@Generable` has no `Date` conformance

Both OS 27 `FoundationModels` swiftinterfaces (macOS and iOS) list the same
`Generable` conformances: Bool, String, Int, Float, Double, Decimal, Array,
Optional, Never — no `Date`. Tool arguments must carry dates as ISO 8601 strings,
parsed by the tool. `Date.ISO8601FormatStyle` parses; a bare `yyyy-MM-dd` needs a
manual `Calendar.dateComponents` fallback (the style won't parse date-only).

## EventKit quirks that shaped the tools

- `predicateForEvents(withStart:end:calendars:)` **caps any range at four years** —
  a wider range is silently shortened. `list_calendar_events` documents it.
- `fetchRemindersMatchingPredicate:completion:` returns a cancellation token, so
  **the ObjC completion-to-async import is disabled** (methods that return a value
  aren't converted); it must be wrapped in `withCheckedContinuation` by hand.
- The completion's result is `[EKReminder]` (non-Sendable), so the map to the
  package's `PIMReminder` happens inside the continuation closure to satisfy
  Swift 6 region isolation at `resume`.
- Reminder due dates are `NSDateComponents`, with a header note that a set
  calendar must be Gregorian. Convert Date↔components on the user's `Calendar`;
  leaving the components' `calendar` nil (as `calendar.dateComponents` does) is fine.
- `EKEvent.location` getter returns the structured location's title; the setter
  creates a structured location. `location`/`notes` live on the `EKCalendarItem` base.
- Stable identities: `EKEvent.eventIdentifier` (events), `EKCalendarItem.calendarItemIdentifier`
  (reminders), `CNContact.identifier`. These are the update/delete handles the list
  tools print as `[id: …]`.

## TCC / authorization

- EventKit authorization statuses on OS 27 include `.writeOnly` (calendar): reads
  under write-only access throw a named error while writes proceed; the package
  requests full access.
- `CNContactStore.unifiedContact(withIdentifier:keysToFetch:)` imports as
  **non-optional, throwing** (not-found throws rather than returning nil) — unlike
  the macOS-only/migrated API shapes. Lookups must catch to produce a `nil`.
- The usage-description keys (`NSCalendarsFullAccessUsageDescription`,
  `NSCalendarsWriteOnlyAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`,
  `NSContactsUsageDescription`) are **not present in any SDK header** — they're
  Apple's Info.plist reference, not framework constants. They cannot be verified
  from the SDK; they are the canonical names per Apple's documentation.
- TCC prompts cannot be automated, so the framework-backed stores are tested only
  by a host; the package's offline suite runs against store-protocol fakes.

## Concurrency

`EKEventStore` and `CNContactStore` are documented thread-safe, so the concrete
stores are `@unchecked Sendable` — a deliberate, commented call. `Date.FormatStyle`
uses the machine locale, so date assertions in tests pin
`en_US_POSIX`/GMT and normalize the narrow no-break space (U+202F) that locale
typography inserts before AM/PM.
