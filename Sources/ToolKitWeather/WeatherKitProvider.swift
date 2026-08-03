import CoreLocation
import Foundation
import WeatherKit

// REQ: FR-111 — the WeatherKit-backed WeatherProviding. WeatherService is
// @unchecked Sendable per the framework; this provider is stateless. Any service
// error maps to `unavailable`, which names the entitlement (the tool cannot
// request an entitlement — only the host can carry it).

public struct WeatherKitProvider: WeatherProviding {
    public init() {}

    public func weather(latitude: Double, longitude: Double) async throws -> WeatherReport {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather: Weather
        do {
            weather = try await WeatherService.shared.weather(for: location)
        } catch {
            throw ToolWeatherError.unavailable
        }

        let current = weather.currentWeather
        let days = weather.dailyForecast.forecast
        let today = days.first
        return WeatherReport(
            temperatureCelsius: current.temperature.converted(to: .celsius).value,
            feelsLikeCelsius: current.apparentTemperature.converted(to: .celsius).value,
            condition: current.condition.rawValue,
            symbolName: current.symbolName,
            highCelsius: today?.highTemperature.converted(to: .celsius).value ?? 0,
            lowCelsius: today?.lowTemperature.converted(to: .celsius).value ?? 0,
            windKilometersPerHour: current.wind.speed.converted(to: .kilometersPerHour).value,
            humidity: current.humidity,
            date: current.date,
            forecast: days.prefix(4).map { day in
                DayForecast(
                    date: day.date,
                    highCelsius: day.highTemperature.converted(to: .celsius).value,
                    lowCelsius: day.lowTemperature.converted(to: .celsius).value,
                    condition: day.condition.rawValue,
                    symbolName: day.symbolName
                )
            }
        )
    }
}
