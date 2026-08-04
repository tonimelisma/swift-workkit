# Top-up D — ToolKitPlaces: crashes, leaks, deprecations, units

## Source
2026-08-03 review of PRs #17/#18/#19. ROADMAP item **1.d**.

## Code changes

### High smells → real fixes

1. **`MapKitPlaceLookup` force-unwraps `MKMapItem.location`** (review smell #4)
   — `:135-136` and `:146-147`. POIs and directions-only items can carry
   `location == nil`. Switch to `guard let coord = mapItem.location?.coordinate`
   in `placemark(from:)` and `place(from:)`; skip the entry or use a sentinel.
   Tests: a fake-side test where the lookup forwards nil `location` cannot be
   exercised here (the fake doesn't construct `MKMapItem`s); this is a known
   framework-path gap in toolkit-live (PR G).

2. **`ToolPlacesError.serviceFailure` is dead code** (review smell #5).
   `MapKitPlaceLookup.directionsETA` (`:121`) calls `MKDirections.calculateETA()`
   raw, so a real `MKDirections` failure bubbles up as an opaque `Error`. Wrap
   with `do/catch { throw ToolPlacesError.serviceFailure("\(error)") }`. Same
   treatment for `searchPlaces` (`:105`) and `geocode`/`reverseGeocode`
   `mapItems` accessors if needed (re-check; the deprecation of `MKPlacemark`
   doesn't apply here, those throw internally already). Add a fake variant
   that throws a `serviceFailure` so the structured-error contract is tested.

3. **`directionsETA` no-origin path uses `MKMapItem.forCurrentLocation()` without
   the TCC ladder** (review smell #7). The description says "Requires the host
   app's `NSLocationWhenInUseUsageDescription` only when no explicit origin is
   given" but the code path skips the authorization check
   `currentLocation()` runs at `:38-51`. Decision: **route the no-origin case
   through the same authorization ladder** — factor the auth sequence out of
   `currentLocation()` into a private `ensureLocationAuthorized() async throws`
   on the lookup, call it from both `currentLocation()` and the no-origin
   branch of `directionsETA`. The lookup protocol gets a sibling method so
   the places tool can route the no-origin decision itself but the auth runs
   server-side (in the lookup impl). The description's promise is now actually
   enforced; a denial throws `.accessDenied` on either path, not an opaque ETA
   failure.

4. **`NetworkStatus.current()` has no timeout** (review smell #10) —
   `Sources/ToolKitSystem/SystemInfoTool.swift:90-97`. If `NWPathMonitor`'s
   `AsyncSequence` is slow the tool wedges the agent loop indefinitely. Wrap
   with the same `withThrowingTaskGroup` + `Task.sleep(for: .seconds(5))`
   pattern `currentLocation` uses. On timeout, return `"unknown"` rather than
   hanging. Document the 5s timeout in the `system_info` description's
   network row.

### Blocker (MapKit deprecations #6)

5. **Refactor `directionsETA` to use a `RouteEndpoint` enum so the address
   path reuses geocoded `MKMapItem`s directly.** Today:
   ```swift
   func directionsETA(from origin: LocationReading?, toLatitude: Double, toLongitude: Double) async throws -> RouteETA
   ```
   forces the tool to pre-geocode addresses to coordinates, then forces the
   lookup to reconstruct an `MKMapItem` from coordinates via the deprecated
   `MKPlacemark.init(coordinate:)` → `MKMapItem.init(placemark:)` chain. The
   build warnings at `MapKitPlaceLookup.swift:111` and `:115` cite that exact
   chain. After refactor:
   ```swift
   public enum RouteEndpoint: Sendable, Equatable {
       case currentLocation
       case coordinates(latitude: Double, longitude: Double)
       case address(String)
   }
   public protocol PlaceLookup: Sendable {
       ...
       func directionsETA(from origin: RouteEndpoint, to destination: RouteEndpoint) async throws -> RouteETA
   }
   ```
   In `MapKitPlaceLookup.directionsETA`:
   - `.currentLocation` → `MKMapItem.forCurrentLocation()` (already non-deprecated).
   - `.address(String)` → `MKGeocodingRequest(addressString:).mapItems.first` —
     reuses MapKit's own placemark, not a hand-built `MKPlacemark(coordinate:)`.
     Throw `.noResult` if no mapItems returned.
   - `.coordinates(lat, lon)` → fall back to `MKMapItem(placemark:
     MKPlacemark(coordinate:))` with an `// noqa: deprecation` comment naming
     it as a known MapKit gap: Apple's OS 26 deprecation of `MKPlacemark(coordinate:)`
     has no public replacement for the coordinate-only path, so the warning
     stays until they ship one. Document this in `docs/research/native-tool-candidates.md`
     and in ENGINEERING.md so the gap is named, not hidden.

   In `DirectionsETATool.call`, build `RouteEndpoint` from arguments:
   - destination: `to` if address, else `to_latitude`+`to_longitude`, else error.
   - origin: `from` if address, else `from_latitude`+`from_longitude`, else
     `.currentLocation` (which now triggers the auth ladder in the lookup).

### Nits

6. **Redundant `, Sendable`** on `MapKitPlaceLookup: PlaceLookup, Sendable`
   (review nit #13) — `PlaceLookup` already requires `: Sendable` (PlaceLookup.swift:71).
   Drop the trailing one.

7. **Units in descriptions** (review nit #20) — `DirectionsETATool.call` outputs
   `%.1f km` but the description doesn't name the unit. Add a sentence: "Distance
   is in kilometers, travel time in minutes." The same for `GetWeatherTool`:
   description should say "temperature in °C, wind in km/h" if the impl uses
   metric — verify by reading WeatherKitProvider.swift.

## Tests added

8. **`directionsETASurfacesServiceFailure`** — fake lookup variant that throws
   `ToolPlacesError.serviceFailure("routing failed")` from `directionsETA`.
   Assert the tool surfaces that (not an opaque error).

9. **`directionsETANoOriginHitsAuthLadder`** — fake lookup that records whether
   its `directionsETA` was called with `.currentLocation` origin; assert the
   tool passes `.currentLocation` when neither `from` nor `from_latitude` is
   supplied. The actual TCC behavior is a host-app gap; this asserts the tool
   pumps it through the right path.

10. **`directionsETAAddressReusesGeocodedMapItem`** — fake lookup that records
    the destination endpoint form; assert that when `to: "Mission District"` is
    given, the lookup receives `.address("Mission District")`, not
    pre-geocoded coordinates. This is the regression guard for the deprecation
    refactor: the tool shouldn't pre-geocode; the lookup handles it.

11. **`directionsETACoordinatesEndpointPreservedForRawInput`** — when the
    model passes `to_latitude`/`to_longitude` directly, the lookup receives
    `.coordinates(...)`. Assert both.

12. **`systemInfoNetworkHasTimeoutFallback`** —
    `Tests/ToolKitSystemTests/SystemInfoToolTests.swift` — inject a fake
    network monitor that never emits; assert the tool returns `"unknown"` for
    the network row within a few seconds rather than hanging. This requires
    the seam in `SystemInfoTool` to accept a network-status provider (it
    already does — check `NetworkStatus` shape).

## Verification
- `swift build` clean on macOS; verify the 3 pre-existing `MKPlacemark` warnings
  are gone for the address path. The coordinate-only path keeps a warning,
  documented as a known MapKit gap.
- `swift test`: 188 + ~4 new (NetworkStatus test + 3 places tests).
- `xcodebuild -destination 'generic/platform=iOS' build`: clean.

## Docs
- `PRODUCT.md` FR-105 entry: note that address origins/destinations reuse
  MapKit's geocoded `MKMapItem` directly (no coordinate reconstruction via
  deprecated `MKPlacemark.init(coordinate:)`); the raw-coordinate path keeps
  the deprecated init as a named MapKit gap.
- `PRODUCT.md` FR-107 entry: append the 5s network-status timeout.
- `ENGINEERING.md` native-capabilities section: add a bullet about the
  `RouteEndpoint` refactor and the remaining coordinate-path deprecation.
- `docs/research/native-tool-candidates.md` note: research the MKPlacemark
  deprecation alternatives; document the verification gap on the
  coordinate-only path.

## What "done" deletes
- This plan file deleted on merge.
- ROADMAP item 1.d row removed once merged.