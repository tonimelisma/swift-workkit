import Foundation

// REQ: FR-111 — the weather seam. Tools depend on it, never on WeatherKit
// directly, so weather is testable offline. WeatherKit is the one tool here that
// needs an Apple-developer entitlement (`com.apple.developer.weatherkit`) — the
// honest cost the research flagged — so the provider's failure path names it.

public struct DayForecast: Sendable, Equatable {
    public var date: Date
    public var highCelsius: Double
    public var lowCelsius: Double
    public var condition: String
    public var symbolName: String

    public init(date: Date, highCelsius: Double, lowCelsius: Double, condition: String, symbolName: String) {
        self.date = date
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.condition = condition
        self.symbolName = symbolName
    }
}

public struct WeatherReport: Sendable, Equatable {
    public var temperatureCelsius: Double
    public var feelsLikeCelsius: Double
    public var condition: String
    public var symbolName: String
    public var highCelsius: Double
    public var lowCelsius: Double
    public var windKilometersPerHour: Double
    public var humidity: Double
    public var date: Date
    public var forecast: [DayForecast]

    public init(
        temperatureCelsius: Double,
        feelsLikeCelsius: Double,
        condition: String,
        symbolName: String,
        highCelsius: Double,
        lowCelsius: Double,
        windKilometersPerHour: Double,
        humidity: Double,
        date: Date,
        forecast: [DayForecast]
    ) {
        self.temperatureCelsius = temperatureCelsius
        self.feelsLikeCelsius = feelsLikeCelsius
        self.condition = condition
        self.symbolName = symbolName
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.windKilometersPerHour = windKilometersPerHour
        self.humidity = humidity
        self.date = date
        self.forecast = forecast
    }
}

public protocol WeatherProviding: Sendable {
    func weather(latitude: Double, longitude: Double) async throws -> WeatherReport
}

public enum ToolWeatherError: LocalizedError, Equatable, Sendable {
    case unavailable
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Weather is unavailable. WeatherKit needs the com.apple.developer.weatherkit entitlement on the host app (Apple Developer setup) — see the tool's documentation."
        case let .invalidArguments(message):
            message
        }
    }
}
