import Foundation
import FoundationModels
import ToolSupport

// REQ: FR-104 — search_places: Apple Maps local search ("coffee near me").
// No location permission is required — a region is only a hint.

@Generable
public struct SearchPlacesArguments: Sendable {
    @Guide(description: "What to search for, e.g. 'coffee'")
    public var query: String
    @Guide(description: "Latitude to search near (with longitude)")
    public var latitude: Double?
    @Guide(description: "Longitude to search near (with latitude)")
    public var longitude: Double?
    @Guide(description: "Maximum results (default 10, max 20)")
    public var limit: Int?

    public init(query: String, latitude: Double? = nil, longitude: Double? = nil, limit: Int? = nil) {
        self.query = query
        self.latitude = latitude
        self.longitude = longitude
        self.limit = limit
    }
}

public struct SearchPlacesTool: Tool, Sendable {
    public let name = "search_places"
    public let description = """
    Search Apple Maps for nearby places ("coffee", "pharmacy"). Optionally \
    provide latitude and longitude to search near a specific point.
    """

    private let lookup: any PlaceLookup

    public init(lookup: any PlaceLookup = MapKitPlaceLookup()) {
        self.lookup = lookup
    }

    public func call(arguments: SearchPlacesArguments) async throws -> String {
        guard arguments.query.nilIfEmpty != nil else {
            throw ToolPlacesError.invalidArguments("query must not be empty.")
        }
        let places = try await lookup.searchPlaces(
            query: arguments.query, latitude: arguments.latitude, longitude: arguments.longitude
        )
        return PlaceOutput.list(places, limit: max(1, min(arguments.limit ?? 10, 20))) { place in
            var parts: [String] = []
            if let category = place.category { parts.append("(\(category))") }
            parts.append("\(place.latitude), \(place.longitude)")
            if let phone = place.phoneNumber { parts.append(phone) }
            if let url = place.url { parts.append(url) }
            return "\(place.name) \(parts.joined(separator: " · "))"
        }
    }
}
