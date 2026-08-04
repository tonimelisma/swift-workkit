# Top-up C — ToolKitPhotos: blockers + the path-helper divergence

## Source
2026-08-03 review of PRs #17/#18/#19. ROADMAP item **1.c**. Three blockers
here, one of them a path-escape security issue; this is the most
security/correctness-urgent PR of the remaining set.

## Code changes

### Blockers

1. **`export_photo` lets an agent write anywhere via unsanitized `filename`** —
   `Sources/ToolKitPhotos/ExportPhotoTool.swift:46`. Strip path components and
   traversal segments from `filename` *before* joining it onto `root`. Policy:
   reject any `filename` containing `/`, `\`, or `..` segments (catches
   `../evil.png`, absolute paths, and Windows-style separators), with an
   `invalidArguments` throw that names what the model did wrong. Also update
   the `@Guide` to say "filename only — no path components." Finally,
   `root.standardizedFileURL.resolvingSymlinksInPath()` (today only standardized)
   so the post-write containment check is robust on iOS where `/var` symlinks
   to `/private/var`, and `FileToolPath.relative` prefix matching works.

2. **`SystemPhotoLibrary.search` is a Swift-Array data race** — `:61`. Drop
   `.concurrent` from `PHFetchResult.enumerateObjects(options:)`. Default
   serial enumeration is fine; the `limit` cap doesn't benefit from
   concurrency. `stop.pointee = true` and array mutation are now single-
   threaded.

3. **`SystemPhotoLibrary.assetData` swallows the framework error** — `:77-84`.
   Switch `withCheckedContinuation` → `withThrowingContinuation`; in the
   completion handler:
   ```swift
   if let error {
       continuation.resume(throwing: ToolPhotosError.exportFailed(error.localizedDescription))
   } else {
       continuation.resume(returning: buffer)
   }
   ```
   The empty-buffer guard now fires only on a successful-but-empty fetch
   (unusual, but still named as `exportFailed("empty data for resource")`).

### Smell

4. **`FileToolPathPhotos.relative` divergence** — `ExportPhotoTool.swift:56-65`
   duplicates `FileToolPath.relative` (in `ToolKitFiles/FileToolSupport.swift:47`)
   but drops `resolvingSymlinksInPath()`. On iOS where the workspace temp dir
   is symlinked `/var → /private/var`, the prefix-comparison check fails and
   `relative` returns the absolute path — leaking the host's sandbox path
   to the model. Make `ToolKitPhotos` depend on `ToolKitFiles` in
   `Package.swift`, `import ToolKitFiles` in `ExportPhotoTool.swift`, delete
   `FileToolPathPhotos`, and use the canonical `FileToolPath.relative(_:to:)`
   helper.

5. **Stateless struct marked `@unchecked Sendable`** —
   `SystemPhotoLibrary` carries no instance state (just `public init() {}`),
   so `@unchecked Sendable` is unnecessary. Drop the annotation; keep the
   Photos framework thread-safety comment as a doc comment.

## Tests added

6. **`exportPhotoRejectsPathTraversal`** — blocker #1 regression:
   - `filename: "../escape.png"` → throws `invalidArguments` naming path
     components.
   - `filename: "/etc/passwd"` → same.
   - `filename: "subdir/legit.png"` → same (no `/` permitted at all).
   - `filename: "legit.png"` → succeeds, writes `root/legit.png`, reports
     "Exported legit.png (N bytes)".
   - `filename: ".."` → throws.

7. **`FakePhotoLibrary.honorsRequestedID`** — fix a near-tautology in the
   existing `exportWritesCopy`: the fake's `assetData(id:)` ignores its `id`
   argument. Add a `requestedIDs: [String] = []` recorder and assert the
   existing test path passes `"p1"` as the requested id (silent regression
   catcher if the tool stops forwarding the id).

8. **`assetDataSurfacesFrameworkFailure`** — blocker #3 shape: extend
   `FakePhotoLibrary` with `var exportError: ToolPhotosError?`; when set,
   `assetData(id:)` throws. Test: set
   `exportError = ToolPhotosError.exportFailed("network down")`, call
   `ExportPhotoTool`, expect throw with that message. Same shape applies to
   the real `SystemPhotoLibrary.assetData` resume path once a host drives
   a real `PHAssetResourceManager` failure through it.

## Verification
- `swift build` clean.
- `swift test`: ToolKitPhotosTests 4 → ~6 (two new). Suite total 199 → ~201.
- `xcodebuild ... -destination 'generic/platform=iOS' build` clean.

## Docs
- `PRODUCT.md` FR-110 entry: append filename sanitization ("no path
  components — `/` and `..` are rejected with the offending filename named").
- `ENGINEERING.md` "Native capabilities" section: add a "Path sanitization
  for `export_photo`" note explaining that `filename` is a leaf, not a path;
  the agent's reach is the host workspace root and nowhere else.

## What "done" deletes
- This plan file deleted on merge.
- ROADMAP item 1.c row removed once merged.