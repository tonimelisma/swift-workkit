import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-105 — directions_eta: travel time and distance to a destination.
// Addresses resolve through geocoding first; a missing origin means the device's
// current location (which needs location permission, unlike an explicit origin).

@Generable
public struct DirectionsETAArguments: Sendable {
    @Guide(description: "Destination address")
    public var to: String?
    @Guide(description: "Destination latitude (with to_longitude)")
    public var to_latitude: Double?
    @Guide(description: "Destination longitude (with to_latitude)")
    public var to_longitude: Double?
    @Guide(description: "Origin address (default: current location)")
    public var from: String?
    @Guide(description: "Origin latitude (with from_longitude)")
    public var from_latitude: Double?
    @Guide(description: "Origin longitude (with from_latitude)")
    public var from_longitude: Double?

    public init(
        to: String? = nil,
        to_latitude: Double? = nil,
        to_longitude: Double? = nil,
        from: String? = nil,
        from_latitude: Double? = nil,
        from_longitude: Double? = nil
    ) {
        self.to = to
        self.to_latitude = to_latitude
        self.to_longitude = to_longitude
        self.from = from
        self.from_latitude = from_latitude
        self.from_longitude = from_longitude
    }
}

public struct DirectionsETATool: Tool, Sendable {
    public let name = "directions_eta"
    public let description = """
    Get the travel time and distance to a destination, from an optional origin \
    (default: the device's current location). The destination is an address or \
    to_latitude/to_longitude; the origin is an address, from_latitude/from_longitude, \
    or omitted. Distance is in kilometers, travel time in minutes. Requires \
    the host app's NSLocationWhenInUseUsageDescription only when no explicit \
    origin is given.
    """

    private let lookup: any PlaceLookup

    public init(lookup: any PlaceLookup = MapKitPlaceLookup()) {
        self.lookup = lookup
    }

    public func call(arguments: DirectionsETAArguments) async throws -> String {
        let destination = try resolveDestination(arguments)
        let origin = try resolveOrigin(arguments)
        let eta = try await lookup.directionsETA(from: origin, to: destination)
        let transport = eta.transportType.map { " (\($0))" } ?? ""
        let km = eta.distanceMeters / 1000
        return "ETA \(Int(eta.minutes.rounded())) min · \(String(format: "%.1f", km)) km\(transport)"
    }

    private func resolveDestination(_ arguments: DirectionsETAArguments) throws -> RouteEndpoint {
        if let address = arguments.to.nilIfEmpty {
            return .address(address)
        }
        if let latitude = arguments.to_latitude, let longitude = arguments.to_longitude {
            return .coordinates(latitude: latitude, longitude: longitude)
        }
        throw ToolPlacesError.invalidArguments("directions_eta needs a destination: an address or latitude/longitude.")
    }

    private func resolveOrigin(_ arguments: DirectionsETAArguments) throws -> RouteEndpoint {
        if let address = arguments.from.nilIfEmpty {
            return .address(address)
        }
        if let latitude = arguments.from_latitude, let longitude = arguments.from_longitude {
            return .coordinates(latitude: latitude, longitude: longitude)
        }
        return .currentLocation
    }
}
