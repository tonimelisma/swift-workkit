import Foundation
import Testing
@testable import ToolKitPlaces

// REQ: FR-102..FR-105 — places tool contracts against a fake lookup. Live
// location needs TCC + hardware, and geocoding/search/ETA are network calls;
// the offline suite asserts argument handling, formatting, and denial
// propagation, and the framework paths are a named host-app gap.

private struct FakePlaceLookup: PlaceLookup {
    var reading = LocationReading(
        latitude: 37.7749, longitude: -122.4194,
        horizontalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 0)
    )
    var geocodeResults: [Placemark] = []
    var reverseResults: [Placemark] = []
    var searchResults: [Place] = []
    var eta = RouteETA(minutes: 14, distanceMeters: 4200, transportType: "driving")
    var injectedError: ToolPlacesError?

    func currentLocation() async throws -> LocationReading {
        if let injectedError { throw injectedError }
        return reading
    }

    func geocode(address: String) async throws -> [Placemark] {
        if let injectedError { throw injectedError }
        return geocodeResults
    }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [Placemark] {
        if let injectedError { throw injectedError }
        return reverseResults
    }

    func searchPlaces(query: String, latitude: Double?, longitude: Double?) async throws -> [Place] {
        if let injectedError { throw injectedError }
        return searchResults
    }

    func directionsETA(from: LocationReading?, toLatitude: Double, toLongitude: Double) async throws -> RouteETA {
        if let injectedError { throw injectedError }
        return eta
    }
}

@Test("FR-102: get_location formats coordinates, accuracy, and timestamp")
func getLocationFormats() async throws {
    let tool = GetLocationTool(lookup: FakePlaceLookup())
    let output = try await tool.call(arguments: .init())
    #expect(output == "37.7749, -122.4194\nAccuracy: ±5 m\nAt: 1970-01-01T00:00:00Z")
}

@Test("FR-102: a location denial propagates named")
func locationDenialPropagates() async throws {
    var lookup = FakePlaceLookup()
    lookup.injectedError = .accessDenied
    let tool = GetLocationTool(lookup: lookup)
    await #expect(throws: ToolPlacesError.accessDenied) {
        _ = try await tool.call(arguments: .init())
    }
}

@Test("FR-103: geocode forward mode formats placemarks")
func geocodeForward() async throws {
    var lookup = FakePlaceLookup()
    lookup.geocodeResults = [Placemark(name: "1 Infinite Loop", fullAddress: "Cupertino, CA", latitude: 37.3317, longitude: -122.0302)]
    let tool = GeocodeTool(lookup: lookup)
    let output = try await tool.call(arguments: .init(address: "1 Infinite Loop"))
    #expect(output == "1. 1 Infinite Loop — Cupertino, CA — 37.3317, -122.0302")
}

@Test("FR-103: geocode reverse mode and no-argument validation")
func geocodeReverseAndValidation() async throws {
    var lookup = FakePlaceLookup()
    lookup.reverseResults = [Placemark(name: "Embarcadero", fullAddress: "San Francisco", latitude: 37.7936, longitude: -122.3965)]
    let tool = GeocodeTool(lookup: lookup)
    let reverse = try await tool.call(arguments: .init(latitude: 37.7936, longitude: -122.3965))
    #expect(reverse.contains("Embarcadero"))
    await #expect(throws: ToolPlacesError.invalidArguments("geocode needs an address, or latitude and longitude together.")) {
        _ = try await tool.call(arguments: .init())
    }
}

@Test("FR-104: search_places formats results and validates the query")
func searchPlacesFormats() async throws {
    var lookup = FakePlaceLookup()
    lookup.searchResults = [Place(name: "Blue Bottle", phoneNumber: "+1-555-0100", url: "https://bluebottle.com", category: "cafe", latitude: 37.775, longitude: -122.418)]
    let tool = SearchPlacesTool(lookup: lookup)
    let output = try await tool.call(arguments: .init(query: "coffee"))
    #expect(output.contains("1. Blue Bottle (cafe) · 37.775, -122.418 · +1-555-0100 · https://bluebottle.com"))
    await #expect(throws: ToolPlacesError.invalidArguments("query must not be empty.")) {
        _ = try await tool.call(arguments: .init(query: " "))
    }
}

@Test("FR-105: directions_eta formats the route and resolves an address destination")
func directionsETAFormats() async throws {
    var lookup = FakePlaceLookup()
    lookup.geocodeResults = [Placemark(name: nil, fullAddress: nil, latitude: 37.7749, longitude: -122.4194)]
    let tool = DirectionsETATool(lookup: lookup)
    let output = try await tool.call(arguments: .init(to: "Mission District", from_latitude: 37.5, from_longitude: -122.3))
    #expect(output == "ETA 14 min · 4.2 km (driving)")
}

@Test("FR-105: directions_eta validates a missing destination")
func directionsETARequiresDestination() async throws {
    let tool = DirectionsETATool(lookup: FakePlaceLookup())
    await #expect(throws: ToolPlacesError.invalidArguments("directions_eta needs a destination: an address or latitude/longitude.")) {
        _ = try await tool.call(arguments: .init())
    }
}
