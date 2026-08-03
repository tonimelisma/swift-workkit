import Foundation
import Photos
import UniformTypeIdentifiers

// REQ: FR-109, FR-110 — the Photos-backed PhotoLibrary. PHPhotoLibrary and
// PHAssetResourceManager are documented thread-safe, so this is @unchecked
// Sendable. Authorization accepts .limited too — a partial grant is still a
// working library for search/export.

public struct SystemPhotoLibrary: PhotoLibrary, @unchecked Sendable {
    public init() {}

    public func requestAccess() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined, .denied, .restricted:
            throw ToolPhotosError.accessDenied
        @unknown default:
            throw ToolPhotosError.accessDenied
        }
    }

    public func search(type: PhotoAssetType?, startDate: Date?, endDate: Date?, album: String?, limit: Int) async throws -> [PhotoAsset] {
        let options = PHFetchOptions()
        var predicates: [NSPredicate] = []
        if let startDate {
            predicates.append(NSPredicate(format: "creationDate >= %@", startDate as NSDate))
        }
        if let endDate {
            predicates.append(NSPredicate(format: "creationDate < %@", endDate as NSDate))
        }
        if let type {
            switch type {
            case .image:
                predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
            case .video:
                predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
            case .screenshot:
                // Screenshots are images with the photoScreenshot subtype; the
                // post-fetch filter below handles it since predicates can't.
                predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
            }
        }
        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetch: PHFetchResult<PHAsset>
        if let album {
            guard let collection = albumCollection(named: album) else { return [] }
            fetch = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            fetch = PHAsset.fetchAssets(with: options)
        }

        var assets: [PHAsset] = []
        let count = min(fetch.count, max(limit, 1))
        fetch.enumerateObjects(options: [.concurrent]) { asset, _, stop in
            if assets.count >= count { stop.pointee = true; return }
            if type == .screenshot, !asset.mediaSubtypes.contains(.photoScreenshot) { return }
            assets.append(asset)
        }
        return assets.map(asset(from:))
    }

    public func assetData(id: String) async throws -> (data: Data, fileExtension: String) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw ToolPhotosError.notFound(id: id)
        }
        guard let resource = PHAssetResource.assetResources(for: asset).first else {
            throw ToolPhotosError.exportFailed("no asset resource")
        }
        let ext = (resource.originalFilename as NSString).pathExtension.lowercased()
        let data: Data = await withCheckedContinuation { continuation in
            var buffer = Data()
            PHAssetResourceManager.default().requestData(for: resource, options: nil) { chunk in
                buffer.append(chunk)
            } completionHandler: { _ in
                continuation.resume(returning: buffer)
            }
        }
        guard !data.isEmpty else {
            throw ToolPhotosError.exportFailed("empty data for resource")
        }
        return (data, ext)
    }

    private func albumCollection(named title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", title)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }

    private func asset(from asset: PHAsset) -> PhotoAsset {
        let type: PhotoAssetType
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            type = .screenshot
        } else if asset.mediaType == .video {
            type = .video
        } else {
            type = .image
        }
        return PhotoAsset(
            id: asset.localIdentifier,
            type: type,
            creationDate: asset.creationDate ?? .distantPast,
            pixelWidth: Int(asset.pixelWidth),
            pixelHeight: Int(asset.pixelHeight),
            title: nil,
            album: nil
        )
    }
}
