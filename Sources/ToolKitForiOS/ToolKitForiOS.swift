// REQ: FR-100 — ToolKitForiOS: the iOS/iPadOS mirror of ToolKitForMac. The domain
// targets are cross-platform, so this umbrella is pure re-export — an app imports
// one product and gets the platform-true set. The one platform difference lives
// inside ToolKitFiles: on iOS a host constructs the file tools with a
// security-scoped root (FR-101), not a plain path root.
@_exported import ToolKitFiles
@_exported import ToolKitInteraction
@_exported import ToolKitNotifications
@_exported import ToolKitPhotos
@_exported import ToolKitPIM
@_exported import ToolKitPlaces
@_exported import ToolKitSystem
@_exported import ToolKitWeather
@_exported import ToolKitWeb
