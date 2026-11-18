import CoreLocation
import Foundation
import WeatherKit

enum Weather {
    static func current(_ id: String, latitude: Double, longitude: Double) {
        Task {
            var report = await fromWeatherKit(latitude, longitude)
            if report == nil { report = await OpenMeteo.report(latitude, longitude) }
            if let report {
                answerRequest(id, "ok", ["weather": report])
            } else {
                answerRequest(id, "error", "unavailable")
            }
        }
    }

    private static func fromWeatherKit(_ latitude: Double, _ longitude: Double) async -> [String: Any]? {
        let place = CLLocation(latitude: latitude, longitude: longitude)
        guard let (now, days, hours, minutes) = try? await WeatherService.shared.weather(
                  for: place, including: .current, .daily, .hourly, .minute),
              let attribution = try? await WeatherService.shared.attribution else { return nil }
        let today = days.forecast.first
        let coming = hours.forecast.filter { $0.date >= now.date.addingTimeInterval(-3600) }.prefix(25)
        let rainSoon = minutes.map { $0.forecast.contains { $0.precipitationChance >= 0.3 } }
            ?? (coming.first.map { $0.precipitationChance >= 0.3 } ?? false)
        return [
            "source": "weatherkit",
            "temperature": now.temperature.converted(to: .celsius).value,
            "feels_like": now.apparentTemperature.converted(to: .celsius).value,
            "humidity": now.humidity,
            "wind": now.wind.speed.converted(to: .kilometersPerHour).value,
            "high": today?.highTemperature.converted(to: .celsius).value as Any,
            "low": today?.lowTemperature.converted(to: .celsius).value as Any,
            "condition": kind(now.condition.rawValue),
            "description": now.condition.description,
            "symbol": now.symbolName,
            "cloud_cover": now.cloudCover,
            "rain_soon": rainSoon,
            "hourly": coming.map { hour in
                [
                    "time": hour.date.timeIntervalSince1970,
                    "temperature": hour.temperature.converted(to: .celsius).value,
                    "daylight": hour.isDaylight
                ] as [String: Any]
            },
            "attribution": [
                "name": attribution.serviceName,
                "url": attribution.legalPageURL.absoluteString,
                "logo_light": attribution.combinedMarkLightURL.absoluteString,
                "logo_dark": attribution.combinedMarkDarkURL.absoluteString
            ]
        ]
    }

    private static func kind(_ condition: String) -> String {
        let name = condition.lowercased()
        let kinds: [(String, [String])] = [
            ("thunderstorm", ["thunder", "tropical", "hurricane"]),
            ("snow", ["snow", "flurries", "sleet", "blizzard", "freezing", "hail", "wintry"]),
            ("drizzle", ["drizzle"]),
            ("rain", ["rain", "showers"]),
            ("fog", ["fog", "haze", "smok", "dust", "blowing"]),
            ("partly_cloudy", ["partly", "mostlyclear", "sunshowers"]),
            ("cloudy", ["cloud"]),
            ("clear", ["clear", "hot", "frigid", "windy", "breezy"])
        ]
        return kinds.first { _, words in words.contains { name.contains($0) } }?.0 ?? "unknown"
    }
}

enum OpenMeteo {
    static func report(_ latitude: Double, _ longitude: Double) async -> [String: Any]? {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,cloud_cover"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "hourly", value: "temperature_2m,is_day,precipitation_probability"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2")
        ]
        guard let url = parts?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let now = json["current"] as? [String: Any] else { return nil }
        let daily = json["daily"] as? [String: Any]
        let hourly = hours(json["hourly"] as? [String: Any] ?? [:], from: (now["time"] as? NSNumber)?.doubleValue ?? 0)
        return [
            "source": "open_meteo",
            "temperature": now["temperature_2m"] as Any,
            "feels_like": now["apparent_temperature"] as Any,
            "humidity": ((now["relative_humidity_2m"] as? NSNumber)?.doubleValue ?? 0) / 100,
            "wind": now["wind_speed_10m"] as Any,
            "high": (daily?["temperature_2m_max"] as? [Any])?.first as Any,
            "low": (daily?["temperature_2m_min"] as? [Any])?.first as Any,
            "condition": kind((now["weather_code"] as? NSNumber)?.intValue ?? -1),
            "cloud_cover": ((now["cloud_cover"] as? NSNumber)?.doubleValue ?? 0) / 100,
            "rain_soon": hourly.first?.rain ?? false,
            "hourly": hourly.map { ["time": $0.time, "temperature": $0.temperature, "daylight": $0.daylight] as [String: Any] },
            "attribution": ["name": "Open-Meteo.com", "url": "https://open-meteo.com/"]
        ]
    }

    private static func hours(_ hourly: [String: Any], from now: Double) -> [(time: Double, temperature: Double, daylight: Bool, rain: Bool)] {
        let times = (hourly["time"] as? [NSNumber] ?? []).map(\.doubleValue)
        let temperatures = (hourly["temperature_2m"] as? [Any] ?? []).map { ($0 as? NSNumber)?.doubleValue }
        let days = (hourly["is_day"] as? [Any] ?? []).map { ($0 as? NSNumber)?.intValue == 1 }
        let rain = (hourly["precipitation_probability"] as? [Any] ?? []).map { (($0 as? NSNumber)?.doubleValue ?? 0) >= 30 }
        let first = times.firstIndex { $0 > now - 3600 } ?? 0
        return times.indices.dropFirst(first).prefix(25).compactMap { index in
            guard index < temperatures.count, let temperature = temperatures[index] else { return nil }
            return (times[index], temperature, index < days.count ? days[index] : true, index < rain.count ? rain[index] : false)
        }
    }

    static func kind(_ code: Int) -> String {
        switch code {
        case 0: "clear"
        case 1, 2: "partly_cloudy"
        case 3: "cloudy"
        case 45, 48: "fog"
        case 51...57: "drizzle"
        case 61...67, 80...82: "rain"
        case 71...77, 85, 86: "snow"
        case 95...99: "thunderstorm"
        default: "unknown"
        }
    }
}
