import CoreLocation
import Foundation
import MapKit

// REQ: FR-102..FR-105 — the CoreLocation + MapKit-backed PlaceLookup. Stateless,
// so it needs no Sendable escape hatch. Authorization is checked and requested
// inside the location path (a denial names the TCC key); geocoding uses the
// MapKit requests CLGeocoder was deprecated in favor of on OS 26+ (verified
// against both SDKs 2026-08-02).

public enum ToolPlacesError: LocalizedError, Equatable, Sendable {
    case accessDenied
    case locationUnavailable
    case noResult(String)
    case invalidArguments(String)
    case serviceFailure(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Location access was denied. Add NSLocationWhenInUseUsageDescription to the host app's Info.plist and grant access in System Settings."
        case .locationUnavailable:
            "Couldn't get the current location (no fix within the timeout)."
        case let .noResult(query):
            "No result for '\(query)'."
        case let .invalidArguments(message):
            message
        case let .serviceFailure(message):
            "The maps service failed: \(message)"
        }
    }
}

public struct MapKitPlaceLookup: PlaceLookup, Sendable {
    public init() {}

    public func currentLocation() async throws -> LocationReading {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined:
            await manager.requestWhenInUseAuthorization()
            guard manager.authorizationStatus != .denied, manager.authorizationStatus != .restricted else {
                throw ToolPlacesError.accessDenied
            }
        case .denied, .restricted:
            throw ToolPlacesError.accessDenied
        @unknown default:
            throw ToolPlacesError.accessDenied
        }

        return try await withThrowingTaskGroup(of: LocationReading.self) { group in
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw ToolPlacesError.locationUnavailable
            }
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location, location.horizontalAccuracy >= 0 {
                        return LocationReading(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            horizontalAccuracy: location.horizontalAccuracy,
                            timestamp: location.timestamp
                        )
                    }
                }
                throw ToolPlacesError.locationUnavailable
            }
            defer { group.cancelAll() }
            guard let reading = try await group.next() else {
                throw ToolPlacesError.locationUnavailable
            }
            return reading
        }
    }

    public func geocode(address: String) async throws -> [Placemark] {
        guard let request = MKGeocodingRequest(addressString: address) else {
            throw ToolPlacesError.invalidArguments("'\(address)' isn't a valid address.")
        }
        let mapItems = try await request.mapItems
        return mapItems.map(placemark(from:))
    }

    public func reverseGeocode(latitude: Double, longitude: Double) async throws -> [Placemark] {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)) else {
            throw ToolPlacesError.invalidArguments("Invalid coordinates.")
        }
        let mapItems = try await request.mapItems
        return mapItems.map(placemark(from:))
    }

    public func searchPlaces(query: String, latitude: Double?, longitude: Double?) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let latitude, let longitude {
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            request.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map(place(from:))
    }

    public func directionsETA(from origin: LocationReading?, toLatitude: Double, toLongitude: Double) async throws -> RouteETA {
        let request = MKDirections.Request()
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: toLatitude, longitude: toLongitude)
        ))
        if let origin {
            request.source = MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
            ))
        } else {
            request.source = MKMapItem.forCurrentLocation()
        }
        let eta = try await MKDirections(request: request).calculateETA()
        return RouteETA(
            minutes: eta.expectedTravelTime / 60,
            distanceMeters: eta.distance,
            transportType: transportName(eta.transportType)
        )
    }

    // MARK: - Mapping

    private func placemark(from mapItem: MKMapItem) -> Placemark {
        Placemark(
            name: mapItem.name,
            fullAddress: mapItem.address?.fullAddress,
            latitude: mapItem.location.coordinate.latitude,
            longitude: mapItem.location.coordinate.longitude
        )
    }

    private func place(from mapItem: MKMapItem) -> Place {
        Place(
            name: mapItem.name ?? "Unnamed",
            phoneNumber: mapItem.phoneNumber,
            url: mapItem.url?.absoluteString,
            category: mapItem.pointOfInterestCategory?.rawValue,
            latitude: mapItem.location.coordinate.latitude,
            longitude: mapItem.location.coordinate.longitude
        )
    }

    private func transportName(_ type: MKDirectionsTransportType) -> String? {
        switch type {
        case .automobile: "driving"
        case .walking: "walking"
        case .transit: "transit"
        case .any: nil
        default: nil
        }
    }
}
