import Foundation

// REQ: FR-109, FR-110 — the photo-library seam. Tools depend on it, never on
// Photos directly: a real library needs TCC + device data nothing can automate.
// The photo library is read-only here — search and export a copy; delete/move/
// album writes were explicitly out of scope in research (native-tool-candidates.md).

public enum PhotoAssetType: String, Sendable, Equatable {
    case image
    case video
    case screenshot
}

/// A photo-library asset, as read from the store. `id` is the stable local
/// identifier the export tool takes back.
public struct PhotoAsset: Sendable, Equatable {
    public var id: String
    public var type: PhotoAssetType
    public var creationDate: Date
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var title: String?
    public var album: String?

    public init(id: String, type: PhotoAssetType, creationDate: Date, pixelWidth: Int, pixelHeight: Int, title: String?, album: String?) {
        self.id = id
        self.type = type
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.title = title
        self.album = album
    }
}

public protocol PhotoLibrary: Sendable {
    func requestAccess() async throws
    func search(type: PhotoAssetType?, startDate: Date?, endDate: Date?, album: String?, limit: Int) async throws -> [PhotoAsset]
    /// The asset's original bytes and filename extension, for export.
    func assetData(id: String) async throws -> (data: Data, fileExtension: String)
}

public enum ToolPhotosError: LocalizedError, Equatable, Sendable {
    case accessDenied
    case notFound(id: String)
    case exportFailed(String)
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Photo library access was denied. Add NSPhotoLibraryUsageDescription to the host app's Info.plist and grant access in System Settings."
        case let .notFound(id):
            "No photo with id \(id) was found. List photos first — the id must come from that output."
        case let .exportFailed(message):
            "The photo export failed: \(message)"
        case let .invalidArguments(message):
            message
        }
    }
}
