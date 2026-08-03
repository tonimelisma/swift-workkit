import AppKit
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ToolKitFiles

// REQ: FR-106 — ocr_image contract. The happy path runs real Vision OCR on a
// generated bitmap (large bold text OCRs reliably; the residual flakiness of
// on-device recognition is named, not hidden). Real-world image variety is a
// host-app gap.

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func drawTextImage(_ text: String, to url: URL) throws {
    let width = 1400, height = 400
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw FileToolError.unsupportedFormat("generation") }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 120, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(
        string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
    ))
    context.textPosition = CGPoint(x: 60, y: 140)
    CTLineDraw(line, context)
    guard let image = context.makeImage() else { throw FileToolError.unsupportedFormat("generation") }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw FileToolError.unsupportedFormat("generation")
    }
}

@Test("FR-106: ocr_image reads the text out of a generated image")
func ocrReadsText() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try drawTextImage("HELLO WORKKIT", to: root.appendingPathComponent("text.png"))

    let tool = OcrImageTool(root: root)
    let output = try await tool.call(arguments: .init(path: "text.png"))
    #expect(output.contains("HELLO"))
    #expect(output.contains("WORKKIT"))
}

@Test("FR-106: ocr_image works through a security-scoped root")
func ocrThroughScopedRoot() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try drawTextImage("SCOPED", to: root.appendingPathComponent("text.png"))

    let tool = OcrImageTool(root: root, securityScopedRoot: root)
    let output = try await tool.call(arguments: .init(path: "text.png"))
    #expect(output.contains("SCOPED"))
}

@Test("FR-106: ocr_image reports a missing file")
func ocrReportsMissingFile() async throws {
    let tool = OcrImageTool(root: tempDirectory())
    await #expect(throws: FileToolError.notFound(path: "nope.png")) {
        _ = try await tool.call(arguments: .init(path: "nope.png"))
    }
}
