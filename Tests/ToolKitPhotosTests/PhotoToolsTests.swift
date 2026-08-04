import Foundation
import Testing
@testable import ToolKitPhotos

// REQ: FR-109, FR-110 — photo tool contracts against a fake library. A real
// library needs TCC + device data; the offline suite asserts formatting, date
// validation, and export's file behavior.

private final class FakePhotoLibrary: PhotoLibrary, @unchecked Sendable {
    var assets: [PhotoAsset] = []
    var exportData: (Data, String) = (Data([0x01, 0x02]), "png")
    var denyAccess = false
    var exportNotFound = false
    /// When set, `assetData(id:)` throws this — simulating a real
    /// `PHAssetResourceManager` failure (iCloud-only asset not downloaded,
    /// network error, cancellation). Pre-2026-08-03 the real impl swallowed
    /// such failures and resumed with a partial buffer; the throwing
    /// continuation now surfaces them, and the fake mirrors that.
    var exportError: ToolPhotosError?
    /// Records the ids requested via `assetData` so `exportWritesCopy` and
    /// friends prove the tool forwards the id — a silent regression catcher
    /// if `export_photo` stops forwarding.
    var requestedIDs: [String] = []

    func requestAccess() async throws {
        if denyAccess { throw ToolPhotosError.accessDenied }
    }

    func search(type: PhotoAssetType?, startDate: Date?, endDate: Date?, album: String?, limit: Int) async throws -> [PhotoAsset] {
        assets
    }

    func assetData(id: String) async throws -> (data: Data, fileExtension: String) {
        requestedIDs.append(id)
        if exportNotFound { throw ToolPhotosError.notFound(id: id) }
        if let exportError { throw exportError }
        return exportData
    }
}

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("FR-109: search_photos formats assets with ids")
func searchFormats() async throws {
    let library = FakePhotoLibrary()
    library.assets = [PhotoAsset(
        id: "p1", type: .screenshot, creationDate: Date(timeIntervalSince1970: 0),
        pixelWidth: 1080, pixelHeight: 1920, title: nil, album: nil
    )]
    let tool = SearchPhotosTool(library: library)
    let output = try await tool.call(arguments: .init())
    #expect(output.contains("1. screenshot · 1970-01-01T00:00:00Z · 1080×1920"))
    #expect(output.contains("[id: p1]"))
}

@Test("FR-109: search_photos validates type and date range")
func searchValidates() async throws {
    let tool = SearchPhotosTool(library: FakePhotoLibrary())
    await #expect(throws: ToolPhotosError.invalidArguments("type must be 'image', 'video', or 'screenshot'; got 'documents'.")) {
        _ = try await tool.call(arguments: .init(type: "documents"))
    }
    await #expect(throws: ToolPhotosError.invalidArguments("end_date must be after start_date.")) {
        _ = try await tool.call(arguments: .init(start_date: "2026-08-05", end_date: "2026-08-04"))
    }
}

@Test("FR-110: export_photo writes a copy into the root and reports the path")
func exportWritesCopy() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = FakePhotoLibrary()
    library.exportData = (Data("photo-bytes".utf8), "png")
    let tool = ExportPhotoTool(library: library, root: root)
    let output = try await tool.call(arguments: .init(id: "p1"))
    #expect(output == "Exported p1.png (11 bytes)")
    #expect(library.requestedIDs == ["p1"], "the tool must forward the requested id — silently breaking this would let export_photo copy any asset regardless of the model's choice")
    let written = try Data(contentsOf: root.appendingPathComponent("p1.png"))
    #expect(written == Data("photo-bytes".utf8))
}

@Test("FR-110: export_photo rejects an existing name and a missing id")
func exportValidates() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = FakePhotoLibrary()
    let tool = ExportPhotoTool(library: library, root: root)
    let output = try await tool.call(arguments: .init(id: "p1", filename: "existing.png"))
    try Data("x".utf8).write(to: root.appendingPathComponent("existing.png"))
    await #expect(throws: ToolPhotosError.invalidArguments("existing.png already exists in the workspace; pick a different filename.")) {
        _ = try await tool.call(arguments: .init(id: "p1", filename: "existing.png"))
    }
    library.exportNotFound = true
    await #expect(throws: ToolPhotosError.notFound(id: "gone")) {
        _ = try await tool.call(arguments: .init(id: "gone"))
    }
    _ = output
}

// MARK: - 2026-08-03 review top-up C: path sanitization + framework error surface

@Test("FR-110: export_photo rejects path traversal in filename (review top-up C)")
func exportRejectsPathTraversal() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = FakePhotoLibrary()
    let tool = ExportPhotoTool(library: library, root: root)

    // Parent-directory traversal — would have escaped under the old join.
    await #expect(throws: ToolPhotosError.invalidArguments(
        "filename '../escape.png' must be a leaf — no path separators. The file lands inside the workspace root."
    )) {
        _ = try await tool.call(arguments: .init(id: "p1", filename: "../escape.png"))
    }

    // Absolute path.
    await #expect(throws: ToolPhotosError.invalidArguments(
        "filename '/etc/passwd' must be a leaf — no path separators. The file lands inside the workspace root."
    )) {
        _ = try await tool.call(arguments: .init(id: "p1", filename: "/etc/passwd"))
    }

    // Subdir slash — even a "legitimate" subdir is not allowed; only a leaf.
    await #expect(throws: ToolPhotosError.invalidArguments(
        "filename 'subdir/legit.png' must be a leaf — no path separators. The file lands inside the workspace root."
    )) {
        _ = try await tool.call(arguments: .init(id: "p1", filename: "subdir/legit.png"))
    }

    // Bare ".." — directory reference, not a leaf.
    await #expect(throws: ToolPhotosError.invalidArguments(
        "filename '..' must be a leaf and not a directory reference."
    )) {
        _ = try await tool.call(arguments: .init(id: "p1", filename: ".."))
    }

    // Backslash separator (Windows-style) — also rejected.
    await #expect(throws: ToolPhotosError.invalidArguments(
        "filename 'sub\\legit.png' must be a leaf — no path separators. The file lands inside the workspace root."
    )) {
        _ = try await tool.call(arguments: .init(id: "p1", filename: "sub\\legit.png"))
    }

    // Sanity: a plain leaf name still works.
    let output = try await tool.call(arguments: .init(id: "p1", filename: "legit.png"))
    #expect(output == "Exported legit.png (2 bytes)")
}

@Test("FR-110: export_photo surfaces a framework error instead of swallowing it (review top-up C)")
func exportSurfacesFrameworkError() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let library = FakePhotoLibrary()
    library.exportError = ToolPhotosError.exportFailed("network down")
    let tool = ExportPhotoTool(library: library, root: root)
    await #expect(throws: ToolPhotosError.exportFailed("network down")) {
        _ = try await tool.call(arguments: .init(id: "p1"))
    }
    // No file should have been written; the fetch failed before the write.
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}
