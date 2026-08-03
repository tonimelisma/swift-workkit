import Foundation
import FoundationModels

// REQ: FR-102 — get_location: a one-shot fix, formatted for the model. The host
// carries NSLocationWhenInUseUsageDescription; a denial is named by the store.

@Generable
public struct GetLocationArguments: Sendable {
    public init() {}
}

public struct GetLocationTool: Tool, Sendable {
    public let name = "get_location"
    public let description = """
    Get the device's current location (latitude, longitude, accuracy). \
    Consequential for privacy — confirm with the user before calling. Requires \
    the host app's NSLocationWhenInUseUsageDescription.
    """

    private let lookup: any PlaceLookup

    public init(lookup: any PlaceLookup = MapKitPlaceLookup()) {
        self.lookup = lookup
    }

    public func call(arguments: GetLocationArguments) async throws -> String {
        let reading = try await lookup.currentLocation()
        let when = reading.timestamp.formatted(.iso8601)
        return "\(reading.latitude), \(reading.longitude)\nAccuracy: ±\(Int(reading.horizontalAccuracy)) m\nAt: \(when)"
    }
}
