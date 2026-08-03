import Foundation
import FoundationModels

// REQ: FR-111 — get_weather: current conditions plus a short forecast. Takes
// explicit coordinates — the model composes with get_location/geocode rather
// than the tool reaching for a location permission of its own.

@Generable
public struct GetWeatherArguments: Sendable {
    @Guide(description: "Latitude of the location")
    public var latitude: Double
    @Guide(description: "Longitude of the location")
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct GetWeatherTool: Tool, Sendable {
    public let name = "get_weather"
    public let description = """
    Current conditions and a short forecast for a location (latitude and \
    longitude, e.g. from get_location or geocode). Requires the host app's \
    com.apple.developer.weatherkit entitlement.
    """

    private let provider: any WeatherProviding
    private let timeZone: TimeZone

    public init(
        provider: any WeatherProviding = WeatherKitProvider(),
        timeZone: TimeZone = .current
    ) {
        self.provider = provider
        self.timeZone = timeZone
    }

    public func call(arguments: GetWeatherArguments) async throws -> String {
        guard (-90 ... 90).contains(arguments.latitude), (-180 ... 180).contains(arguments.longitude) else {
            throw ToolWeatherError.invalidArguments("Invalid coordinates: latitude −90…90, longitude −180…180.")
        }
        let report = try await provider.weather(
            latitude: arguments.latitude, longitude: arguments.longitude
        )
        let day = report.date.formatted(.iso8601)
        var lines: [String] = []
        lines.append("\(round1(report.temperatureCelsius))°C (feels \(round1(report.feelsLikeCelsius))°C) · \(report.condition) at \(day)")
        lines.append("High/low: \(round1(report.highCelsius))°C / \(round1(report.lowCelsius))°C · Wind \(round1(report.windKilometersPerHour)) km/h · Humidity \(Int(report.humidity * 100))%")
        for forecast in report.forecast {
            lines.append("\(forecast.date.formatted(.iso8601)): \(forecast.condition) — \(round1(forecast.highCelsius))°C / \(round1(forecast.lowCelsius))°C")
        }
        return lines.joined(separator: "\n")
    }

    private func round1(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
