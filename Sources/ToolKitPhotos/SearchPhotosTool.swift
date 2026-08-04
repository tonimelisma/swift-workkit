import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-109 — search_photos: read-only discovery of the photo library, with
// stable ids for export_photo. Type, date range, album, and limit narrow it.

@Generable
public struct SearchPhotosArguments: Sendable {
    @Guide(description: "Filter by type: 'image', 'video', or 'screenshot'")
    public var type: String?
    @Guide(description: "Only photos created at or after this — ISO 8601 or a date")
    public var start_date: String?
    @Guide(description: "Only photos created before this — ISO 8601 or a date")
    public var end_date: String?
    @Guide(description: "Only photos in this album")
    public var album: String?
    @Guide(description: "Maximum photos to return (default 30)")
    public var limit: Int?

    public init(type: String? = nil, start_date: String? = nil, end_date: String? = nil, album: String? = nil, limit: Int? = nil) {
        self.type = type
        self.start_date = start_date
        self.end_date = end_date
        self.album = album
        self.limit = limit
    }
}

public struct SearchPhotosTool: Tool, Sendable {
    public let name = "search_photos"
    public let description = """
    Search the photo library by type, date range, and album. The [id] is the \
    handle export_photo takes. Requires the host app's NSPhotoLibraryUsageDescription.
    """

    private let library: any PhotoLibrary
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(
        library: any PhotoLibrary = SystemPhotoLibrary(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.library = library
        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func call(arguments: SearchPhotosArguments) async throws -> String {
        let type = try parseType(arguments.type)
        let start = try arguments.start_date.map { try PIMDatePhotos.parse($0, calendar: calendar, timeZone: timeZone) }
        let end = try arguments.end_date.map { try PIMDatePhotos.parse($0, calendar: calendar, timeZone: timeZone) }
        if let start, let end, start >= end {
            throw ToolPhotosError.invalidArguments("end_date must be after start_date.")
        }
        try await library.requestAccess()
        let assets = try await library.search(
            type: type, startDate: start, endDate: end, album: arguments.album.nilIfEmpty,
            limit: max(1, arguments.limit ?? 30)
        )
        return PhotoOutput.list(assets) { asset in
            let when = asset.creationDate.formatted(.iso8601)
            return "\(asset.type.rawValue) · \(when) · \(asset.pixelWidth)×\(asset.pixelHeight)\n   [id: \(asset.id)]"
        }
    }

    private func parseType(_ raw: String?) throws -> PhotoAssetType? {
        switch raw?.lowercased() {
        case nil: nil
        case "image": .image
        case "video": .video
        case "screenshot": .screenshot
        case let other?:
            throw ToolPhotosError.invalidArguments("type must be 'image', 'video', or 'screenshot'; got '\(other)'.")
        }
    }
}

/// ISO 8601 / bare-date parsing, local to this product.
enum PIMDatePhotos {
    static func parse(_ raw: String, calendar: Calendar, timeZone: TimeZone) throws -> Date {
        var style = Date.ISO8601FormatStyle()
        style.timeZone = timeZone
        if let date = try? Date(raw, strategy: style) { return date }
        let parts = raw.split(separator: "-")
        if parts.count == 3,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.timeZone = timeZone
            if let date = calendar.date(from: components) { return date }
        }
        throw ToolPhotosError.invalidArguments(
            "Couldn't parse '\(raw)' as a date. Use ISO 8601 (2026-08-02T15:00:00Z) or a date (2026-08-02)."
        )
    }
}

enum PhotoOutput {
    static func list<T>(_ all: [T], line: (T) -> String) -> String {
        guard !all.isEmpty else { return "[No results]" }
        return all.enumerated().map { "\($0.offset + 1). \(line($0.element))" }.joined(separator: "\n")
    }
}
