import Foundation
import FoundationModels
import Vision

// REQ: FR-106 — ocr_image: text out of an image file, filling the gap read_file
// left when it deferred image support (FR-074). Returns String — the Tool
// protocol's output — rather than waiting on a multi-modal Tool.Output. On-device
// (Vision), no network, no permission: the file root already grants the path.

@Generable
public struct OcrImageArguments: Sendable {
    @Guide(description: "Absolute path, or relative to the tool's working directory")
    public var path: String
    @Guide(description: "Slower but more accurate recognition (default true); false prefers speed")
    public var accurate: Bool?

    public init(path: String, accurate: Bool? = nil) {
        self.path = path
        self.accurate = accurate
    }
}

public struct OcrImageTool: Tool, Sendable {
    public let name = "ocr_image"
    public let description = """
    Read the text out of an image file (screenshot, photo, scanned page) and \
    return it as text. Supports the same paths as read_file. \
    [Output not shown] — returns the recognized text.
    """

    private let root: URL
    private let securityScopedRoot: URL?

    public init(root: URL, securityScopedRoot: URL? = nil) {
        // REQ: FR-101 — same as the file tools: scoped roots are stored as-granted.
        self.securityScopedRoot = securityScopedRoot
        self.root = securityScopedRoot ?? root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func call(arguments: OcrImageArguments) async throws -> String {
        try await SecurityScopedAccess.withScopedAccess(to: securityScopedRoot) {
            try await perform(arguments: arguments)
        }
    }

    private func perform(arguments: OcrImageArguments) async throws -> String {
        let url = FileToolPath.resolve(arguments.path, root: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileToolError.notFound(path: arguments.path)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = arguments.accurate == false ? .fast : .accurate
        let handler = VNImageRequestHandler(url: url, options: [:])
        // `VNImageRequestHandler.perform(_:)` is synchronous — Vision's
        // ~60s first-call model warmup runs on whichever executor serviced
        // this Tool `call`, which could be the main actor or a high-priority
        // cooperative-pool lane. Offloading onto a detached userInitiated
        // task keeps the main actor free. Reading `request.results` happens
        // inside the same task (no race crossing back) since the Vision
        // types involved (`VNRecognizeTextRequest`, `VNRecognizeTextObservation`)
        // aren't `Sendable` — only the produced `String` crosses the
        // isolation boundary.
        let text: String = try await Task.detached(priority: .userInitiated) { () -> String in
            do {
                try handler.perform([request])
            } catch {
                // Surface Vision failures to the caller; the inner `do/catch`
                // preserves the "wrap as FileToolError.invalidArguments"
                // shape from the pre-detached call.
                throw FileToolError.invalidArguments("Couldn't recognize text in \(arguments.path).")
            }
            let recognized = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return recognized.isEmpty ? "[No text recognized]" : recognized
        }.value
        return text
    }
}
