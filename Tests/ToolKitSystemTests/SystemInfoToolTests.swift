import Foundation
import Network
import Testing
@testable import ToolKitSystem

// REQ: FR-107 — system_info is a pure ProcessInfo/FileManager read plus an
// injected network report; the tests pin the format with a fixed network string.

@Test("FR-107: system_info reports OS, hardware, memory, and injected network")
func systemInfoReports() async throws {
    let tool = SystemInfoTool(networkStatus: { "Wi-Fi (satisfied, not expensive)" })
    let output = try await tool.call(arguments: .init())
    #expect(output.contains("OS: "))
    #expect(output.contains("Memory: "))
    #expect(output.contains("Disk: "))
    #expect(output.contains("Low-power mode: "))
    #expect(output.contains("Thermal state: "))
    #expect(output.contains("Network: Wi-Fi (satisfied, not expensive)"))
}

// MARK: - 2026-08-03 review top-up D: NetworkStatus 5s timeout fallback

/// An AsyncSequence that never emits — simulates a NWPathMonitor that fails
/// to start or hangs (named host-app gap for the real thing; the fake proves
/// the timeout fallback returns "unknown" rather than wedging).
private struct HangingPathSequence: AsyncSequence, Sendable {
    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> NWPath? { nil }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}

@Test("FR-107: NetworkStatus.current returns unknown within the timeout when no path is emitted (review top-up D)")
func networkStatusTimesOut() async throws {
    // Tiny timeout: proves the fallback fires without paying the full 5s in
    // the suite. The fake sequence emits nothing on first next(), so the first
    // task returns nil immediately; the sleeper waits 50ms; "unknown" wins.
    let result = await NetworkStatus.current(paths: HangingPathSequence(), timeout: .milliseconds(50))
    #expect(result == "unknown")
}
