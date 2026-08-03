import Foundation
import Testing
@testable import ToolKitWeather

// REQ: FR-111 — get_weather contract against a fake provider. WeatherKit needs
// the com.apple.developer.weatherkit entitlement, so the live path is a named
// host-app gap; the offline suite pins formatting and validation.

private struct FakeWeatherProvider: WeatherProviding {
    var report = WeatherReport(
        temperatureCelsius: 21.4,
        feelsLikeCelsius: 19.2,
        condition: "Clear",
        symbolName: "sun.max",
        highCelsius: 24.0,
        lowCelsius: 15.0,
        windKilometersPerHour: 12.0,
        humidity: 0.55,
        date: Date(timeIntervalSince1970: 0),
        forecast: [
            DayForecast(date: Date(timeIntervalSince1970: 0), highCelsius: 24, lowCelsius: 15, condition: "Clear", symbolName: "sun.max"),
            DayForecast(date: Date(timeIntervalSince1970: 86_400), highCelsius: 22, lowCelsius: 14, condition: "Cloudy", symbolName: "cloud"),
        ]
    )
    var injectedError: ToolWeatherError?

    func weather(latitude: Double, longitude: Double) async throws -> WeatherReport {
        if let injectedError { throw injectedError }
        return report
    }
}

@Test("FR-111: get_weather formats current conditions and the forecast")
func formatsReport() async throws {
    let tool = GetWeatherTool(provider: FakeWeatherProvider())
    let output = try await tool.call(arguments: .init(latitude: 37.77, longitude: -122.42))
    #expect(output.contains("21.4°C (feels 19.2°C) · Clear at 1970-01-01T00:00:00Z"))
    #expect(output.contains("High/low: 24.0°C / 15.0°C · Wind 12.0 km/h · Humidity 55%"))
    #expect(output.contains("Cloudy — 22.0°C / 14.0°C"))
}

@Test("FR-111: get_weather validates coordinates")
func validatesCoordinates() async throws {
    let tool = GetWeatherTool(provider: FakeWeatherProvider())
    await #expect(throws: ToolWeatherError.invalidArguments("Invalid coordinates: latitude −90…90, longitude −180…180.")) {
        _ = try await tool.call(arguments: .init(latitude: 95, longitude: -122))
    }
    await #expect(throws: ToolWeatherError.invalidArguments("Invalid coordinates: latitude −90…90, longitude −180…180.")) {
        _ = try await tool.call(arguments: .init(latitude: 37, longitude: 181))
    }
}

@Test("FR-111: a provider failure propagates the entitlement-named error")
func unavailablePropagates() async throws {
    var provider = FakeWeatherProvider()
    provider.injectedError = .unavailable
    let tool = GetWeatherTool(provider: provider)
    await #expect(throws: ToolWeatherError.unavailable) {
        _ = try await tool.call(arguments: .init(latitude: 37, longitude: -122))
    }
}
