import CoreLocation
import Foundation
import MapKit

// REQ: FR-102..FR-105 — the CoreLocation + MapKit-backed PlaceLookup. Stateless,
// so it needs no Sendable escape hatch (the `Sendable` conformance follows from
// `PlaceLookup: Sendable`). Authorization is checked and requested inside both
// the location path and the no-origin `directionsETA` branch (a denial names
// the TCC key); geocoding uses the MapKit requests `CLGeocoder` was deprecated
// in favor of on OS 26+ (verified against both SDKs 2026-08-02).

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

public struct MapKitPlaceLookup: PlaceLookup {
    public init() {}

    /// The TCC ladder for read access to current location. Called from both
    /// `currentLocation()` (FR-102) and the no-origin `directionsETA` branch
    /// (FR-105), since `MKMapItem.forCurrentLocation()` resolves a route using
    /// the device's location and so needs the same authorization as a fix would.
    /// The description's promise — "Requires
    /// `NSLocationWhenInUseUsageDescription` only when no explicit origin is
    /// given" — is enforced here, not left to opaque ETA failure behavior on a
    /// denial.
    private func ensureLocationAuthorized() async throws {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return
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
    }

    public func currentLocation() async throws -> LocationReading {
        try await ensureLocationAuthorized()

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
        do {
            let mapItems = try await request.mapItems
            return mapItems.map(placemark(from:))
        } catch {
            throw ToolPlacesError.serviceFailure("\(error)")
        }
    }

    public func reverseGeocode(latitude: Double, longitude: Double) async throws -> [Placemark] {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)) else {
            throw ToolPlacesError.invalidArguments("Invalid coordinates.")
        }
        do {
            let mapItems = try await request.mapItems
            return mapItems.map(placemark(from:))
        } catch {
            throw ToolPlacesError.serviceFailure("\(error)")
        }
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
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map(place(from:))
        } catch {
            throw ToolPlacesError.serviceFailure("\(error)")
        }
    }

    public func directionsETA(from origin: RouteEndpoint, to destination: RouteEndpoint) async throws -> RouteETA {
        let request = MKDirections.Request()
        request.destination = try await mapItem(for: destination, role: "destination")
        request.source = try await mapItem(for: origin, role: "origin")
        do {
            let eta = try await MKDirections(request: request).calculateETA()
            return RouteETA(
                minutes: eta.expectedTravelTime / 60,
                distanceMeters: eta.distance,
                transportType: transportName(eta.transportType)
            )
        } catch {
            throw ToolPlacesError.serviceFailure("\(error)")
        }
    }

    /// Resolves a `RouteEndpoint` to a `MKMapItem` — centralizing geocoding so
    /// the address path reuses MapKit's own `MKMapItem` (no longer throwing it
    /// away to coordinates and reconstructing it via the deprecated
    /// `MKPlacemark.init(coordinate:)`). The `.currentLocation` branch runs the
    /// TCC ladder before returning; a denial propagates as `.accessDenied`,
    /// consistent with `currentLocation()`.
    private func mapItem(for endpoint: RouteEndpoint, role: String) async throws -> MKMapItem {
        switch endpoint {
        case .currentLocation:
            try await ensureLocationAuthorized()
            return MKMapItem.forCurrentLocation()
        case let .address(address):
            guard let request = MKGeocodingRequest(addressString: address) else {
                throw ToolPlacesError.invalidArguments("'\(address)' isn't a valid address.")
            }
            let mapItems: [MKMapItem]
            do {
                mapItems = try await request.mapItems
            } catch {
                throw ToolPlacesError.serviceFailure("\(error)")
            }
            guard let first = mapItems.first else {
                throw ToolPlacesError.noResult("the \(role) address '\(address)'")
            }
            return first
        case let .coordinates(latitude, longitude):
            // Known MapKit gap (review top-up D): Apple deprecated
            // `MKPlacemark.init(coordinate:)` in OS 26+ recommending "use
            // MKMapItem's location, address and addressRepresentations
            // properties instead" — but no public API constructs an `MKMapItem`
            // for raw coordinates without going through a placemark. The
            // address path above avoids this entirely; the coordinate-only path
            // keeps the deprecated init until Apple ships a replacement.
            return MKMapItem(placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            ))
        }
    }

    // MARK: - Mapping

    private func placemark(from mapItem: MKMapItem) -> Placemark {
        // On OS 27, `MKMapItem.location` is non-optional, so `coordinate` is
        // always populated. (Pre-OS 27 this was optional and called for a
        // nil-check; verified against the SDK.)
        return Placemark(
            name: mapItem.name,
            fullAddress: mapItem.address?.fullAddress,
            latitude: mapItem.location.coordinate.latitude,
            longitude: mapItem.location.coordinate.longitude
        )
    }

    private func place(from mapItem: MKMapItem) -> Place {
        return Place(
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
