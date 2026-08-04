import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-110 — export_photo: copy one photo's original bytes into the host's
// writable root (the model's file workspace) and return the relative path. The
// photo library itself is only read; the write lands in the host's own sandbox,
// so no security-scoped access is needed here.

@Generable
public struct ExportPhotoArguments: Sendable {
    @Guide(description: "The [id] from search_photos output")
    public var id: String
    @Guide(description: "Destination filename; default is <id>.<ext>")
    public var filename: String?

    public init(id: String, filename: String? = nil) {
        self.id = id
        self.filename = filename
    }
}

public struct ExportPhotoTool: Tool, Sendable {
    public let name = "export_photo"
    public let description = """
    Copy a photo from the library into the file workspace by its [id] from \
    search_photos, and report the path the model can read. Requires the host \
    app's NSPhotoLibraryUsageDescription.
    """

    private let library: any PhotoLibrary
    private let root: URL

    public init(library: any PhotoLibrary = SystemPhotoLibrary(), root: URL) {
        self.library = library
        self.root = root.standardizedFileURL
    }

    public func call(arguments: ExportPhotoArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw ToolPhotosError.invalidArguments("id must not be empty.")
        }
        try await library.requestAccess()
        let (data, fileExtension) = try await library.assetData(id: arguments.id)
        let filename = arguments.filename.nilIfEmpty
            ?? "\(arguments.id).\(fileExtension.isEmpty ? "bin" : fileExtension)"
        let destination = root.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ToolPhotosError.invalidArguments("\(filename) already exists in the workspace; pick a different filename.")
        }
        try data.write(to: destination, options: .atomic)
        let relative = FileToolPathPhotos.relative(destination, to: root)
        return "Exported \(relative) (\(data.count) bytes)"
    }
}

enum FileToolPathPhotos {
    static func relative(_ url: URL, to root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.path
        }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}
