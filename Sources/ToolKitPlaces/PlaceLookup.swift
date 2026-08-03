import Foundation

// REQ: FR-102..FR-105 — ToolKitPlaces domain values and the lookup seam. The
// tools depend on `PlaceLookup`, never on CoreLocation/MapKit directly, so the
// suite runs offline against fakes: live location needs TCC + hardware, and
// Apple's geocoding/search services are network calls nothing can automate.
// The default MapKit-backed implementation lives in MapKitPlaceLookup.swift.

/// A one-shot location reading.
public struct LocationReading: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double
    public var timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

/// A geocoded address (forward or reverse).
public struct Placemark: Sendable, Equatable {
    public var name: String?
    public var fullAddress: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String?, fullAddress: String?, latitude: Double, longitude: Double) {
        self.name = name
        self.fullAddress = fullAddress
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A local place search result (MKLocalSearch).
public struct Place: Sendable, Equatable {
    public var name: String
    public var phoneNumber: String?
    public var url: String?
    public var category: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, phoneNumber: String?, url: String?, category: String?, latitude: Double, longitude: Double) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.url = url
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Travel-time result (MKDirections ETAResponse).
public struct RouteETA: Sendable, Equatable {
    public var minutes: Double
    public var distanceMeters: Double
    public var transportType: String?

    public init(minutes: Double, distanceMeters: Double, transportType: String?) {
        self.minutes = minutes
        self.distanceMeters = distanceMeters
        self.transportType = transportType
    }
}

public protocol PlaceLookup: Sendable {
    /// The device's current location, one shot.
    func currentLocation() async throws -> LocationReading
    /// Forward-geocode an address string.
    func geocode(address: String) async throws -> [Placemark]
    /// Reverse-geocode coordinates.
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> [Placemark]
    /// Local place search; coordinates narrow the region when given.
    func searchPlaces(query: String, latitude: Double?, longitude: Double?) async throws -> [Place]
    /// Travel time from an origin (nil = current location) to a destination.
    func directionsETA(from: LocationReading?, toLatitude: Double, toLongitude: Double) async throws -> RouteETA
}
