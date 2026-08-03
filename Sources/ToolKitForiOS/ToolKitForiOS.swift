// REQ: FR-100 — ToolKitForiOS: the iOS/iPadOS mirror of ToolKitForMac. The four
// domain targets are cross-platform (EventKit, Contacts, PDFKit, URLSession all
// exist on iOS), so this umbrella is pure re-export — an app imports one product
// and gets the platform-true set. The one platform difference lives inside
// ToolKitFiles: on iOS a host constructs the file tools with a security-scoped
// root (FR-101), not a plain path root.
@_exported import ToolKitFiles
@_exported import ToolKitInteraction
@_exported import ToolKitPIM
@_exported import ToolKitWeb
