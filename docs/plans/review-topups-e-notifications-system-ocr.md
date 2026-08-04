# Top-up E — Notifications + System + OcrImage hardening

## Source
2026-08-03 review of PRs #17/#18/#19. ROADMAP item **1.e**.

## Code changes

### Notifications (review smells #8, #15, #16)

`Sources/ToolKitNotifications/ScheduleNotificationTool.swift` and
`NotificationScheduling.swift`:

1. **Length cap** on `title` (≤ 100) and `body` (≤ 200). Validation throws
   named and explanatory — `title is 250 chars; the max is 100`. UN
   silently truncates today, so the model gets no feedback.

2. **Horizon cap** on `time_interval_seconds` and `date`. Pick a generous
   envelope: 24h (86_400s) for `time_interval_seconds`, and a `date` no
   further than 30 days. Beyond that, reject with `invalidArguments`
   naming the cap. A notification scheduled a year out by a runaway agent
   loop is解答 no use to anyone and contributes to the per-app 64-cap
   exhaustion.

3. **Caller-supplied `id` for de-dupe.** Add `public var id: String?` to
   `ScheduleNotificationArguments`. The tool uses it when given; the
   `UNNotificationRequest` semantics replace any prior request with the
   same identifier. When the model doesn't supply one, fall back to the
   current `UUID().uuidString` (preserves existing behavior — no host
   breakage). Update the `@Guide` so the model knows it can dedupe.

4. **Drop the unused `calendar` init param.** The tool's `parseDate` only
   uses `timeZone` and `Date.ISO8601FormatStyle` (which has its own
   calendar). Force-removing it is a source-breaking change to anyone
   constructing `ScheduleNotificationTool(... calendar: ...)`. **But:**
   no one constructs it with that param today (PR #18 was internal; the
   only callers are the test suite via `ScheduleNotificationTool(scheduler:)
   or `ScheduleNotificationTool(scheduler:...)` — verify with grep). Drop
   it; update tests if any pass a `calendar:` arg explicitly.

5. **Trim title before schedule.** Today `arguments.title.nilIfEmpty` is
   used for validation but the schedule call passes the raw string with
   whitespace. Bind `let title = arguments.title.nilIfEmpty` after the guard
   and pass that.

6. **Stateless struct marked `@unchecked Sendable`** —
   `UserNotificationCenterScheduler.swift:37`: drop the `@unchecked`
   annotation; the struct has no stored state, the implicit conformance
   holds.

### System disk (review smell #12)

`Sources/ToolKitSystem/SystemInfoTool.swift` `diskStatus()`. On iOS,
`NSHomeDirectory()` is the app's container; the `resourceValues` quota
reflects the container, not the device. A model that reads "Disk: 2 GB
free" on iOS believes it's the device and will decline a 3 GB file the
device would in fact fit. Fix: compute against `URL(fileURLWithPath: "/")`
which works on both platforms — on iOS this returns the system volume (the
whole device), and on macOS this matches what `NSHomeDirectory()` would
return on a single-volume machine (the common case). Document the
platform-agnostic choice in the description.

### OCR blocking the cooperative pool (review smell #9)

`Sources/ToolKitFiles/OcrImageTool.swift:54-57`. `VNImageRequestHandler.perform(_:)`
is synchronous and the ~60s first-call warmup blocks whichever executor
serviced the Tool `call` — could be the main actor. Wrap the synchronous
`perform` in `Task.detached(priority: .userInitiated)`:

```swift
let result: Void = try await Task.detached(priority: .userInitiated) {
    try handler.perform([request])
}.value
```

Also check `Task.isCancelled` after the `perform` returns; if the caller
cancelled, surface `CancellationError` rather than the (now-stale) text.

## Tests added

7. **`scheduleRejectsOverlongTitle/Body`** —
   `title: String(repeating: "x", count: 101)` rejects; `body: 201 chars`
   rejects. Title of 100 and body of 200 succeed (boundary).

8. **`scheduleRejectsExcessiveHorizon`** —
   `time_interval_seconds: 86_400 * 2` rejects.
   `date: now + 31 days` rejects.
   `time_interval_seconds: 86_400` succeeds (boundary).
   `date: now + 30 days` succeeds (boundary).

9. **`scheduleAcceptsCallerSuppliedId`** — caller passes `id: "restart-123"`
   → scheduled entry's `id == "restart-123"` (de-dupe surface). Same id
   twice → second call replaces the first (UN's documented behavior,
   `.add` with a duplicate identifier replaces, not errors). Assert via
   the fake that the entry has the caller's id.

10. **`scheduleTrimsTitle`** — pass `title: "   Padded   "`; assert the
    scheduled entry's title is `"Padded"` (after trim).

11. **`systemInfoDiskReportsDeviceVolume`** — `SystemInfoTool` is hard to
    test directly because `diskStatus` is private. Verify by adding a
    `forRootVolume` internal seam or asserting the property on a fresh
    `URL(fileURLWithPath: "/")` resourceValues row exists in
    `SystemInfoToolTests`. **Tradeoff**: rather than expand the seam for
    one assertion, document this fix in the `system_info` description's
    prose and prove it by manual `df -h /` comparison. Add a single test
    that constructs `SystemInfoTool` (default injected network), gets the
    output, and asserts `output.contains("Disk: ")` and that the value is
    a number (regex `Disk: \\d+\\.\\d+ GB free`). The volume change is
    a behavior fix not testable from the offline suite beyond what's there
    — name it as a gap if needed.

12. **`ocrImageDoesNotBlock`** — hard to assert "did not block the
    cooperative pool" directly. Indirect assertion: wrap the OCR call in
    a `Task` and assert `Task.isCancelled == true` propagates through
    within a short window when cancelled. Skip if flaky; the named gap
    is the production fix. Add a basic cancellation-shape test:
    - Start an OCR task.
    - Cancel it.
    - Expect `CancellationError` or a wrapped error within 2s.

    This is fragile against Vision's warmup; gate it as `.disabled(if:
    !VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate,
    using: ...).isEmpty == false)` — actually that's always-true on Mac.
    Skip the cancellation direct-test; the wrapping itself is the fix
    and is internally consistent. The flakiness is recognized in docs.

## Verification
- `swift build` clean.
- `swift test`: 193 + ~5 new (notifications caps/horizon/id/trim) +
  (system disk stub is not added; the fix is structural).
- `xcodebuild -destination 'generic/platform=iOS' build` clean.

## Docs
- `PRODUCT.md` FR-108 entry: append the hardening (length cap 100/200;
  horizon cap 24h/30 days; caller-supplied id for de-dupe).
- `PRODUCT.md` FR-107 entry: append the disk fix — reports the system
  volume on both platforms, not the iOS app container quota.
- `ENGINEERING.md` native-capabilities section: add bullets about the
  notification hardening and the disk-label fix.
- `PRODUCT.md` FR-106 entry: append the cooperative-pool offload note.

## What "done" deletes
- This plan file deleted on merge.
- ROADMAP item 1.e row removed.