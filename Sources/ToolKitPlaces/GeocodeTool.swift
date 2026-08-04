import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-103 — geocode: forward (address → coordinates) or reverse
// (coordinates → address). Uses the MapKit geocoding requests that replaced
// the deprecated CLGeocoder (research: native-tool-candidates.md).

@Generable
public struct GeocodeArguments: Sendable {
    @Guide(description: "Address to geocode")
    public var address: String?
    @Guide(description: "Latitude for reverse geocoding (with longitude)")
    public var latitude: Double?
    @Guide(description: "Longitude for reverse geocoding (with latitude)")
    public var longitude: Double?

    public init(address: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct GeocodeTool: Tool, Sendable {
    public let name = "geocode"
    public let description = """
    Convert between addresses and coordinates. Give either an address (forward) \
    or latitude and longitude (reverse).
    """

    private let lookup: any PlaceLookup

    public init(lookup: any PlaceLookup = MapKitPlaceLookup()) {
        self.lookup = lookup
    }

    public func call(arguments: GeocodeArguments) async throws -> String {
        let placemarks: [Placemark]
        if let address = arguments.address.nilIfEmpty {
            placemarks = try await lookup.geocode(address: address)
        } else if let latitude = arguments.latitude, let longitude = arguments.longitude {
            placemarks = try await lookup.reverseGeocode(latitude: latitude, longitude: longitude)
        } else {
            throw ToolPlacesError.invalidArguments("geocode needs an address, or latitude and longitude together.")
        }
        return PlaceOutput.list(placemarks) { mark in
            var parts = [mark.name, mark.fullAddress].compactMap { $0 }.filter { !$0.isEmpty }
            parts.append("\(mark.latitude), \(mark.longitude)")
            return parts.joined(separator: " — ")
        }
    }
}

/// Shared numbered-list formatting for the places tools (local to this product).
enum PlaceOutput {
    static func list<T>(_ all: [T], limit: Int = 10, line: (T) -> String) -> String {
        guard !all.isEmpty else { return "[No results]" }
        let shown = all.prefix(limit)
        return shown.enumerated().map { "\($0.offset + 1). \(line($0.element))" }.joined(separator: "\n")
    }
}
