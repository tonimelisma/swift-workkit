# Top-up B — ToolKitPIM: blockers + smells + the empty-clears contract

## Source
2026-08-03 full-repo review of PRs #17/#18/#19. ROADMAP item **1.b**.

## Open question resolved during planning
Toni 2026-08-03: "you figure it out!!! what is the correct behavior!" on the
contact "empty clears" question. **Decision (mine, recorded, not inferred):**
`nil` preserves the current value; empty / whitespace clears it (sets to `""`
for `String` drafts, `nil` for `String?` drafts). Rationale:
- It's what the calendar tool's `location`/`notes` overlay already does
  (`arguments.location ?? current.location` — `Optional("")` unwraps to `""`,
  not to `current.location`).
- It's what the file-tool edit ledger says ("an empty location/notes clears").
- It's what the @Guide text already claims on the contact's four name fields
  ("empty string clears it"). The contact code was the outlier; the docs were
  the truth.

## Code changes

### Blockers

1. **`ContactsPIMStore.apply` preserves email/phone labels** (blocker #1,
   silent data loss). Today every save hardcodes `CNLabelHome` /
   `CNLabelPhoneNumberMobile`, so touching a contact wipes any "Work" / "Home
   (landline)" / "Main" labels. Fix: when applying a draft's emails/phones,
   reuse the label from any existing entry whose value string equals the draft
   value (case-insensitive for emails, `stringValue` for phones); new values
   default to `CNLabelHome` / `CNLabelPhoneNumberMobile` as today. Make
   `apply` `internal` (drop `private`) so the test suite can call it directly
   without an EventKit round-trip. Also filter empty/whitespace strings out of
   the draft arrays (review nit #16 — a model that passes `["ada@acme.com", ""]`
   shouldn't create a labeled empty entry).

2. **`update_contact` overlay: empty clears, nil preserves** (blocker #2). In
   `Sources/ToolKitPIM/UpdateContactTool.swift:72-78` replace
   `arguments.X.nilIfEmpty ?? current.X` with:
   ```swift
   let givenName  = arguments.given_name.map  { $0.nilIfEmpty ?? "" } ?? current.givenName
   let familyName = arguments.family_name.map { $0.nilIfEmpty ?? "" } ?? current.familyName
   let org        = arguments.organization.map { $0.nilIfEmpty } ?? current.organization
   let jobTitle   = arguments.job_title.map   { $0.nilIfEmpty } ?? current.jobTitle
   ```
   The `String?` fields (org, jobTitle) drop to nil on empty; the `String`
   fields (given/familyName) drop to `""`. Wire those into `PIMContactDraft`.

3. **Fake contact search ANDs the criteria** (blocker #3). In
   `Tests/ToolKitPIMTests/FakeStores.swift` `MemoryContactStore.search`,
   replace the OR-short-circuit (each `if let` returns) with a single filter
   that ANDs all provided criteria. The real `ContactsPIMStore.search` uses
   `NSCompoundPredicate(andPredicateWithSubpredicates:)`, so the fake must
   match it or the contract tests prove things that aren't true.

4. **`update_calendar_event` no longer re-resolves the calendar when no patch
   was supplied** (blocker #7 — silent event move between duplicate-named
   calendars). In `UpdateCalendarEventTool.swift:99` replace
   `arguments.calendar.nilIfEmpty ?? current.calendarTitle` with
   `arguments.calendar.flatMap { $0.nilIfEmpty }`:
   - `nil` (model didn't pass) → `draft.calendarTitle == nil` → the store's
     `if let calendarTitle = draft.calendarTitle` branch is skipped →
     `event.calendar` stays by id, not by re-resolved title.
   - `""` / whitespace (model passes empty) → also `nil`, treated as "don't
     touch"; clearing an event's calendar isn't a meaningful operation, and
     it's safer than silently moving the event.

5. **Fix `update_calendar_event` title overlay** to the same empty-clears
   contract (`UpdateCalendarEventTool.swift:93`):
   ```swift
   let title = arguments.title.map { $0.nilIfEmpty ?? "" } ?? current.title
   ```
   Leave `location`/`notes` as-is — `arguments.X ?? current.X` already does
   nil-preserves/empty-clears via `Optional(" ?? current.X` semantics (passing
   `""` yields `""` because `Optional("")` is non-nil).

### Smells / nits

6. **`MemoryCalendarStore.events` filter to overlap, not start-in-range** —
   mirror EventKit's `predicateForEvents(withStart:end:calendars:)`. Today the
   fake keeps an event iff `start <= startDate < end`; EventKit keeps any
   event whose range overlaps the query range. New:
   ```swift
   .filter { event in event.startDate < end && event.endDate > start }
   ```
   Add a multi-day event test (event starts yesterday, ends tomorrow; query
   today must return it).

7. **`CompleteReminderTool.swift:5-7` overclaim** — comment says "the
   journal-before-execute guard never double-completes." Drop the journal
   mention; the actual idempotency is the explicit `guard !current.isCompleted`
   check on lines 40-42 that *skips the write*. Same comment fix in
   `UncompleteReminderTool.swift` if it has the same shape — read and decide.

8. **`ListCalendarEventsTool.swift:30` "EventKit caps any range at four years"** —
   unverified Apple-doc claim baked into model-facing prose. Drop the sentence
   from the description; the tool will simply not enforce a cap. Same drop in
   `docs/product/PRODUCT.md` FR-087 if it claims it (check, edit there).

9. **`ListCalendarEventsTool.swift:58` force-unwrap** — replace
   `?? calendar.date(byAdding: .day, value: 1, to: start)!` with a graceful
   fallback (`?? (calendar.date(byAdding: .day, value: 1, to: start) ??
   start.addingTimeInterval(86_400))`).

10. **`UpdateCalendarEventArguments` `calendar` @Guide** — add "first match
    used if duplicated" so the model knows about the duplicate-named-calendar
    ambiguity when it explicitly requests a calendar move.

## Tests added

11. **`updateContactEmptyClearsVsNilPreserves`** — selenium for blockers 1+2:
    construct Ada Lovelace with `givenName=Ada, familyName=Lovelace,
    organization=Acme, jobTitle=Engineer`. Patch with `family_name=""` →
    draft.familyName == `""`. Patch with `family_name=" "` (whitespace) →
    same. Patch with `organization=""` → draft.organization == nil. Patch with
    `job_title=nil` only → other fields preserved.

12. **`updateEventTitleEmptyClearsAndCalendarPreservesById`** — selenium for
    blockers 4, 5 + #6 above. Existing event on calendar "Work" cal-1.
    Title-only patch (`title=""`) → draft.title == `""`, draft.calendarTitle
    == nil (so store preserves by id). Notes-only patch (`notes="x"`) →
    draft.calendarTitle == nil.

13. **`updateEventKeepsCalendarWhenNoneRequested`** — blocker #4 regression:
    two calendars both entitled "Work" (ids cal-1, cal-2). Event currently on
    cal-1. Update only `notes` — assert the fake's new calendar is still
    cal-1 (=`MemoryCalendarStore` already preserved, but add the regression
    guard).

14. **`searchContactsANDsMultipleCriteria`** — blocker #3: Ada with emails
    [ada@acme.com, ada@home.com] phone "+1-555-0100"; Grace with emails
    [grace@navy.mil] same phone "+1-555-0100". Search by name "Ada" AND phone
    "+1-555-0100" → Ada only. Search by name "a" AND email "ada@acme.com" →
    Ada only.

15. **`applyPreservesLabelsForMatchingValues`** + **`applyAssignsDefaultLabelsForNewValues`** —
    blocker #1 sanity. Use the now-`internal` `ContactsPIMStore.apply`
    directly. Build a `CNMutableContact` with
    `emailAddresses=[CNLabeledValue(label: CNLabelWork, value: "ada@acme.com" as NSString),
    CNLabeledValue(label: CNLabelHome, value: "ada@home.com" as NSString)]`. Apply
    a draft with `emails: ["ada@acme.com", "ada@home.com", "ada@new.com"]`.
    Assert: ada@acme.com keeps `CNLabelWork`; ada@home.com keeps `CNLabelHome`;
    ada@new.com gets `CNLabelHome` (the default).

16. **`listCalendarEventsReturnsEventsThatOverlapRange`** — smell #6: multi-day
    event starting yesterday, ending tomorrow; query today's range → returned.
    Existing range-filter tests stay green (the overlap formula is a strict
    superset of start-in-range).

## PRODUCT.md / ENGINEERING.md

- **PRODUCT.md FR-098** entry: append the contract clause ("nil preserves;
  empty/whitespace clears — matching the calendar tool's location/notes overlay
  and the file-tool edit ledger."). Quoting Toni's 2026-08-03 delegation
  ("you figure it out!!! what is the correct behavior!") and noting this is my
  determinate decision.
- **PRODUCT.md FR-089** entry: clarify calendar overlay — `nil` keeps by id,
  `calendar:` re-resolves by title (first match if duplicated).
- **PRODUCT.md FR-087**: drop the "EventKit caps any range at four years" claim
  if present (it is — verify by grep before editing).
- **ENGINEERING.md "Why it is built this way > PIM"**: add "Read-before-write
  overlay contract: nil-preserves / empty-clears" subsection with the rationale
  and Toni's delegation. Add a "Label preservation" note: a patch that includes
  existing email/phone values keeps their labels; new values get the framework
  defaults (`CNLabelHome` / `CNLabelPhoneNumberMobile`).

## Verification
- `swift build` clean (macOS).
- `swift test`: 180 unconditional offline → expect ~187 (180 + 7 new).
- `xcodebuild ... -destination 'generic/platform=iOS' build`: clean.
- No new FR/NFR IDs minted (fixes to FR-086..FR-099).
- Tests are deterministic — no `@Test(.disabled)`, no `.env`-gated.

## What "done" deletes
- This plan file deleted on merge to main.
- The bullets that ROADMAP item 1.b enumerated are now PRODUCT/ENGINEERING
  recorded; the 1.b row in ROADMAP is removed.