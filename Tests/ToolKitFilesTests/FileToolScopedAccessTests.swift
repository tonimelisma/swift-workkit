import Foundation
import Testing
import ZIPFoundation
@testable import ToolKitFiles

// REQ: FR-101 — security-scoped file bodies. A host on iOS constructs the file
// tools with a UIDocumentPicker URL as securityScopedRoot; every call must
// activate the grant around the operation. A temp-directory URL is not actually
// security-scoped, so `startAccessingSecurityScopedResource` returns false and
// the wrapper degrades to a no-op — which is exactly the guarantee macOS relies
// on, and the only path unit-testable without a real (host-granted) scoped URL.
// The real grant activation is a named host-app gap, same honesty rule as TCC.

private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test("FR-101: read_file works through a security-scoped root")
func readFileThroughScopedRoot() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "hello scoped".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

    let tool = ReadFileTool(root: root, ledger: FileReadLedger(), securityScopedRoot: root)
    let output = try await tool.call(arguments: .init(path: "a.txt"))
    #expect(output.contains("hello scoped"))
}

@Test("FR-101: list_folder works through a security-scoped root")
func listFolderThroughScopedRoot() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "x".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

    let tool = ListFolderTool(root: root, securityScopedRoot: root)
    let output = try await tool.call(arguments: .init(path: "."))
    #expect(output.contains("b.txt"))
}

@Test("FR-101: find_files works through a security-scoped root")
func findFilesThroughScopedRoot() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "x".write(to: root.appendingPathComponent("match.md"), atomically: true, encoding: .utf8)

    let tool = FindFilesTool(root: root, securityScopedRoot: root)
    let output = try await tool.call(arguments: .init(pattern: "*.md"))
    #expect(output.contains("match.md"))
}

@Test("FR-101: search_files works through a security-scoped root")
func searchFilesThroughScopedRoot() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try "needle in a haystack".write(to: root.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

    let tool = SearchFilesTool(root: root, securityScopedRoot: root)
    let output = try await tool.call(arguments: .init(pattern: "needle"))
    #expect(output.contains("c.txt"))
}

@Test("FR-101: write_file and edit_file work through a security-scoped root")
func writeAndEditThroughScopedRoot() async throws {
    let root = tempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let ledger = FileReadLedger()

    let writer = WriteFileTool(root: root, ledger: ledger, securityScopedRoot: root)
    _ = try await writer.call(arguments: .init(path: "d.txt", content: "original"))
    let editor = EditFileTool(root: root, ledger: ledger, securityScopedRoot: root)
    _ = try await editor.call(arguments: .init(path: "d.txt", oldString: "original", newString: "edited"))

    let read = try String(contentsOf: root.appendingPathComponent("d.txt"), encoding: .utf8)
    #expect(read == "edited")
}
