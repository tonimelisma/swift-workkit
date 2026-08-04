import Foundation
import FoundationModels
import ToolSupport
import ToolKitFiles

// REQ: FR-110 — export_photo: copy one photo's original bytes into the host's
// writable root (the model's file workspace) and return the relative path. The
// photo library itself is only read; the write lands in the host's own sandbox,
// so no security-scoped access is needed here. `filename` is a leaf, not a path:
// path components and traversal segments are rejected so the agent cannot write
// anywhere outside the host workspace root. The relative-path formatter is
// shared with the file tools (FileToolPath.relative) so symlink resolution
// matches — iOS's temp dir symlinks /var to /private/var and a divergent helper
// would leak the resolved absolute path back to the model.

@Generable
public struct ExportPhotoArguments: Sendable {
    @Guide(description: "The [id] from search_photos output")
    public var id: String
    @Guide(description: "Destination filename (no path components; default is <id>.<ext>)")
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
    search_photos, and report the path the model can read. The filename is a \
    leaf — no path components or '..' segments; the agent can only write inside \
    its workspace. Requires the host app's NSPhotoLibraryUsageDescription.
    """

    private let library: any PhotoLibrary
    private let root: URL

    public init(library: any PhotoLibrary = SystemPhotoLibrary(), root: URL) {
        self.library = library
        // Resolve symlinks so the post-write FileToolPath.relative check (and
        // any containment check) compares on the canonical, inode-stable path.
        // On iOS the temp dir is symlinked /var → /private/var; without this
        // step, root and destination would use different prefixes and relative
        // would silently fall back to leaking the absolute path back to the
        // model.
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func call(arguments: ExportPhotoArguments) async throws -> String {
        guard arguments.id.nilIfEmpty != nil else {
            throw ToolPhotosError.invalidArguments("id must not be empty.")
        }
        try await library.requestAccess()
        let (data, fileExtension) = try await library.assetData(id: arguments.id)
        let filename = try resolvedFilename(arguments.filename, id: arguments.id, fileExtension: fileExtension)
        let destination = root.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ToolPhotosError.invalidArguments("\(filename) already exists in the workspace; pick a different filename.")
        }
        try data.write(to: destination, options: .atomic)
        let relative = FileToolPath.relative(destination, to: root)
        return "Exported \(relative) (\(data.count) bytes)"
    }

    /// Resolves the model's optional `filename` to a sanitized leaf name. The
    /// model has no reach beyond the workspace root — path components and
    /// traversal segments in the proposed filename are rejected explicitly so
    /// a `"../evil.png"` or `"/etc/passwd"` proposal never reaches the file
    /// system. The default is `<id>.<ext>` if no filename is given.
    private func resolvedFilename(_ proposed: String?, id: String, fileExtension: String) throws -> String {
        // When the model didn't supply one, default to `<id>.<ext>` — the
        // id is a stable library local-identifier (Photos framework), so
        // it's already a string of safe characters; never reaches this
        // sanitizer anyway.
        if let proposed {
            return try sanitizeFilename(proposed)
        }
        let ext = fileExtension.isEmpty ? "bin" : fileExtension
        return "\(id).\(ext)"
    }

    private func sanitizeFilename(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolPhotosError.invalidArguments("filename must not be empty.")
        }
        // Reject any path-component marker. The agent's reach is the workspace
        // root only; a path proposal is treated as an attempted escape, not a
        // usability hassle, and the error names the offending filename.
        if trimmed.contains("/") || trimmed.contains("\\") {
            throw ToolPhotosError.invalidArguments(
                "filename '\(trimmed)' must be a leaf — no path separators. The file lands inside the workspace root."
            )
        }
        // `lastPathComponent` is harmless on a separator-free string; if any
        // `..` segment sneaks past (it shouldn't without `/`), reject it
        // explicitly so the agent never writes a directory reference.
        let leaf = (trimmed as NSString).lastPathComponent
        if leaf == "." || leaf == ".." || leaf.isEmpty {
            throw ToolPhotosError.invalidArguments(
                "filename '\(trimmed)' must be a leaf and not a directory reference."
            )
        }
        return leaf
    }
}
