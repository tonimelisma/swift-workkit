import Darwin
import Foundation
import FoundationModels
import Network

// REQ: FR-107 — system_info: a read-only environment report. Everything is a
// pure ProcessInfo/FileManager read except network reachability, which is an
// injected closure (default wraps NWPathMonitor) so tests stay deterministic.

public struct SystemInfoTool: Tool, Sendable {
    public let name = "system_info"
    public let description = """
    Report the device's environment: OS, hardware, memory, disk, power, thermal \
    state, and network reachability. Read-only — no permission needed.
    """

    private let networkStatus: @Sendable () async -> String

    public init(networkStatus: @escaping @Sendable () async -> String = SystemInfoTool.defaultNetworkStatus) {
        self.networkStatus = networkStatus
    }

    /// The production network reachability report (NWPathMonitor-backed).
    public static func defaultNetworkStatus() async -> String {
        await NetworkStatus.current()
    }

    public func call(arguments: SystemInfoArguments) async throws -> String {
        let info = ProcessInfo.processInfo
        let disk = diskStatus()
        var lines: [String] = []
        lines.append("OS: \(info.operatingSystemVersionString)")
        lines.append("Hardware: \(hardwareName()) (\(info.activeProcessorCount) cores, \(info.processorCount) advertised)")
        lines.append("Memory: \(gigabytes(Double(info.physicalMemory))) GB")
        lines.append("Disk: \(disk.free) free of \(disk.total)")
        lines.append("Low-power mode: \(info.isLowPowerModeEnabled ? "on" : "off")")
        lines.append("Thermal state: \(thermalName(info.thermalState))")
        lines.append("Uptime: \(uptime(info.systemUptime))")
        lines.append("Network: \(await networkStatus())")
        return lines.joined(separator: "\n")
    }

    private func diskStatus() -> (free: String, total: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let total = values?.volumeTotalCapacity ?? 0
        return ("\(gigabytes(Double(free))) GB", "\(gigabytes(Double(total))) GB")
    }

    private func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f", bytes / 1_000_000_000)
    }

    private func hardwareName() -> String {
        var machine = [CChar](repeating: 0, count: 128)
        var size = machine.count
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: machine)
    }

    private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

@Generable
public struct SystemInfoArguments: Sendable {
    public init() {}
}

enum NetworkStatus {
    static func current() async -> String {
        let monitor = NWPathMonitor()
        for await path in monitor {
            return format(path)
        }
        return "unknown"
    }

    private static func format(_ path: NWPath) -> String {
        var interfaces: [String] = []
        if path.usesInterfaceType(.wifi) { interfaces.append("Wi-Fi") }
        if path.usesInterfaceType(.cellular) { interfaces.append("cellular") }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.append("wired") }
        if path.usesInterfaceType(.loopback) { interfaces.append("loopback") }
        if interfaces.isEmpty { interfaces.append("other") }
        let status = path.status == .satisfied ? "satisfied"
            : path.status == .requiresConnection ? "requires connection" : "unsatisfied"
        return "\(interfaces.joined(separator: "+")) (\(status)\(path.isExpensive ? ", expensive" : ""))"
    }
}
