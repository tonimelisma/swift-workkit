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

    func requestAccess() async throws {
        if denyAccess { throw ToolPhotosError.accessDenied }
    }

    func search(type: PhotoAssetType?, startDate: Date?, endDate: Date?, album: String?, limit: Int) async throws -> [PhotoAsset] {
        assets
    }

    func assetData(id: String) async throws -> (data: Data, fileExtension: String) {
        if exportNotFound { throw ToolPhotosError.notFound(id: id) }
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
