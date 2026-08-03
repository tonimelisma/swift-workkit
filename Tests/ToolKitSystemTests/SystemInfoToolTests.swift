import Foundation
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
