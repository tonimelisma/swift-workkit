# Native tool candidates: Apple frameworks as agent tools (OS 27)

> **Shipped 2026-08-02:** Tier 1 (location/places, OCR, notifications, system),
> photo library, and weather — FR-102…FR-111 — per Toni ("do all of tier 1, photo
> library, weather"). See PRODUCT.md "Native capabilities"; this doc remains the
> origin record and the home of the unshipped Tier 2–4 evaluation.

What Apple platform APIs could become `ToolKit*` tools, evaluated against the
package's thesis, verified against the macOS 27 and iPhoneOS 27 SDKs on
2026-08-02. This is research, not a roadmap — nothing here is scheduled, and
nothing is minted as an FR until Toni picks from it. Evidence is the SDK header
presence shown below; availability was checked by grep against both SDKs, not
assumed.

## How candidates are judged

Every candidate must survive all of these to be "ship-ready":

1. **Fits the socket.** A `FoundationModels.Tool` returning `String`, with
   `@Generable` arguments — nothing here fails this; they all do.
2. **Local-first, no sign-in.** The PIM principle ("no sign-in, works offline")
   is the baseline. A candidate that needs an account, a server, or a
   developer-entitlement ceremony loses points — WeatherKit below.
3. **Cross-platform.** NFR-010 holds macOS 27 **and** iOS 27. A macOS-only
   candidate is possible but must be flagged (AppleScript below).
4. **TCC/entitlement cost is documented, not zero.** The package's contract is
   "each tool documents the keys its host carries." A candidate's permission
   surface is a real cost, not a footnote.
5. **Read-only vs consequential.** Consequential tools are approval-gated; the
   cost is per-tool.
6. **Not computer use, not shell, not telemetry.** The permanent non-goals are
   the fence: no GUI automation, no `exec`, nothing that phones home.

## Verified availability (2026-08-02, both SDKs unless noted)

| Framework | Key surface | macOS 27 | iOS 27 |
|---|---|---|---|
| CoreLocation | `CLLocationManager`, `requestWhenInUseAuthorization`, `CLGeocoder` reverse/forward geocode | ✓ | ✓ |
| MapKit | `MKLocalSearch`/`MKLocalSearchRequest`, `MKDirections`/`MKDirectionsRequest` | ✓ | ✓ |
| Vision | `VNRecognizeTextRequest` (+`supportedRecognitionLanguages`), `VNImageRequestHandler` | ✓ | ✓ |
| UserNotifications | `UNUserNotificationCenter`, `UNTimeInterval`/`UNCalendarNotificationTrigger` | ✓ | ✓ |
| Network (Swift overlay) | `NWPathMonitor` (a `Sendable` Swift class over `nw_path_monitor_t`) | ✓ | ✓ |
| CoreImage | `CIFilter`, `CIContext` | ✓ | ✓ |
| AVFoundation | `AVAssetExportSession`, presets | ✓ | ✓ |
| Photos | `PHPhotoLibrary` (incl. `.limited` auth), `PHAsset`, `PHFetchOptions` | ✓ | ✓ |
| Speech | `SFSpeechRecognizer`, `SFSpeechURLRecognitionRequest` (file input) | ✓ | ✓ |
| NaturalLanguage | `NLLanguageRecognizer`, `NLEmbedding`, `NLTokenizer` | ✓ | ✓ |
| Translation | `TranslationSession` | ✓ | ✓ |
| HealthKit | `HKHealthStore` (**now on macOS too**, not iOS-only) | ✓ | ✓ |
| HomeKit | `HMHomeManager`, `HMHome` | ✓ | ✓ |
| CoreSpotlight / Spotlight | `NSMetadataQuery` (file search), `CSSearchableIndex` | ✓ | ✓ |
| MediaPlayer | `MPMediaLibrary`, `MPMediaQuery` | ✓ | ✓ |
| ScreenCaptureKit | `SCScreenshotManager` | ✓ | ✓ (iOS 17+, broadcast-ext oriented) |
| Security / Keychain | `SecItemAdd`/`SecItemCopyMatching` | ✓ | ✓ |
| AppKit/UIKit | `NSPasteboard` / `UIPasteboard` (clipboard) | ✓ | ✓ |
| Foundation | `NSAppleScript` — **macOS only** (`API_UNAVAILABLE(ios,…)`) | ✓ | ✗ |

Two notable absences: **no public Notes or Mail framework** (MailKit is a Mail
*extension* API — compose/send inside a Mail extension, not mailbox reads), and
**no public cross-app AppIntents invocation** (Siri/Shortcuts can run them; a
third-party app cannot). Both close doors: Notes/Mail traffic must ride MCP
(which is what ROADMAP item 1 already does for Gmail/Outlook), and AppIntents is
host-side.

## Tier 1 — strong, both platforms, no new auth ceremony

**1. Location & places — `ToolKitPlaces` (CoreLocation + MapKit).**
`get_location` (coarse, host-gated), `geocode`/`reverse_geocode`, `search_places`
(MKLocalSearch), `directions_eta` (MKDirections). The single best complement to
the PIM increment: a calendar event has a `location` string, and "how long will
it take to get there" needs exactly this. Read-only. TCC:
`NSLocationWhenInUseUsageDescription`. Both platforms.

**2. Vision OCR — `ocr_image` (Vision `VNRecognizeTextRequest`).**
Text out of a screenshot/photo/PDF page the model was given a path to. Fills the
hole `read_file` left open when it deferred image support (FR-074's "not in this
increment") — and it returns `String`, which the Tool protocol wants, instead of
waiting on a multi-modal `Tool.Output`. No TCC: it processes a file the user's
already granted (via the file tools' root). Both platforms. On-device, no
network.

**3. Local notifications — `schedule_notification` (UserNotifications).**
A real output channel: "notify me when the run finishes," "remind me in an
hour." `UNTimeInterval`/`UNCalendarNotificationTrigger`, no server, no push
certificate. Scheduling needs no authorization. Consequential in the sense that
it reaches the user, but low-stakes. Both platforms.

**4. System environment — `system_info` (ProcessInfo + Network + sysctl).**
OS version, architecture, memory/disk, low-power mode, thermal state, network
reachability (`NWPathMonitor`), battery. Read-only diagnostic that makes an
agent's other choices smarter ("2 GB free disk" → don't write that file). Cheap,
no TCC. Both platforms.

## Tier 2 — good, with a real cost to weigh

**5. Image manipulation (CoreImage).** `convert_image`: format (PNG/JPEG/HEIC),
resize, rotate, quality. Pairs with the file tools' write path. No TCC. Both
platforms. Value is real but the daily ask is rarer than OCR.

**6. Media transcode (AVFoundation).** `transcode_media`: convert an audio/video
file or extract its audio track. No TCC for user-provided files; heavy under the
hood. Niche-but-real ask ("make this podcast mp3").

**7. Speech transcription (Speech).** `transcribe_audio` on a file the model can
path to. On-device. Costs: the **Speech Recognition entitlement** and a TCC
prompt, both host-side. Files the gap between audio on disk and text the model
can read.

**8. Photo library (Photos).** `search_photos` (by type/date/album), read
metadata, export a copy into the model's file root. The strongest "personal
assistant" candidate — "find the screenshot from Tuesday." Costs:
`NSPhotoLibraryUsageDescription` + add, and any write (delete/move/album) is
consequential. Both platforms.

**9. Weather (WeatherKit).** Current conditions + forecast. The catch: it needs
the **`com.apple.developer.weatherkit` entitlement** — an Apple-developer setup
ceremony per host, the opposite of BYOK-free. Violates "local-first, no setup"
more than any Tier 1 candidate. Ship only if a host explicitly wants it.

## Tier 3 — noted, deferred, or conditional

- **Clipboard (NSPasteboard/UIPasteboard).** Trivial to ship; read is a privacy
  leak vector and write is consequential. Keep in mind, flag the privacy.
- **Natural language (NaturalLanguage).** Language ID, tokenization, embeddings —
  the LLM already does all of this better. Marginal.
- **Translation (Translation).** On-device translation — the LLM does this too.
  Marginal (worth it only for on-device-no-model situations).
- **HomeKit.** Home control ("turn off the lights"). Consequential, needs a
  configured home + `NSHomeKitUsageDescription`, privacy-heavy. Conditional on a
  host that is a home app.
- **HealthKit** (now on macOS too). Needs an entitlement +
  `NSHealthShareUsageDescription`, extreme privacy. Only a narrowly-scoped host
  would opt in.
- **Spotlight / iCloud search (NSMetadataQuery).** "Find my file anywhere" is
  powerful and privacy-heavy; the API has quirks (asynchronous, scope codes). Not
  Tier 1 because the blast radius is the whole machine.
- **Music library (MediaPlayer).** On-device library read; an agent playing or
  curating music is niche.

## Tier 4 — no-go, and why

- **Screen capture (ScreenCaptureKit).** Read-only, but it is the front door to
  computer-use — the permanent non-goal ("Computer use/Accessibility
  (deferred)"). Plus Screen Recording TCC. Do not ship unless the computer-use
  line itself moves.
- **AppleScript / Apple Events (NSAppleScript).** **macOS-only** (verified:
  `API_UNAVAILABLE(ios…)`), so it fails the cross-platform bar outright — and it
  is app control, which the roadmap routes through MCP, not a shell-like tool.
- **Keychain (Security/SecItem).** Giving the model read/write over the user's
  stored credentials is the wrong shape entirely. No-go.
- **Mail / Messages / Notes.** No public read API exists (MailKit is
  extension-only). This is what MCP is for — already roadmap item 1.
- **AppIntents invocation.** No public cross-app invocation. Host-side only.
- **DeviceActivity / Screen Time.** Restricted entitlements; not agent tools.
- **StoreKit.** Purchases are the app's business logic, not the agent's.

## What stands out

Two bundles carry the killer-ask pattern the way PIM did: **location+places
(pairs with calendar events — "how long to my next meeting")** and **OCR (pairs
with the file tools — text out of any image)**. Both are Tier 1: local, no
sign-in, both platforms, no entitlement ceremony, read-only. Weather is the
tempting one that fails the local-first bar on entitlement; screen capture is
the tempting one that fails the non-goal fence. The decision to schedule any of
this is Toni's.
