package cauldron.app

import org.json.JSONArray
import org.json.JSONObject
import java.net.URL
import kotlin.concurrent.thread

/**
 * The weather at a place from Open-Meteo, answered as a `weather` map
 * (`CauldronNative.Weather.Report`), or `unavailable` when it cannot be reached.
 */
object CauldronWeather {
    fun current(request: JSONObject) {
        val id = request.getString("id")
        val latitude = request.optDouble("latitude")
        val longitude = request.optDouble("longitude")
        thread(name = "cauldron-weather") {
            val report = runCatching { fetch(latitude, longitude) }.getOrNull()
            if (report != null) CauldronDevice.answer(id, "ok", JSONObject().put("weather", report))
            else CauldronDevice.answer(id, "error", "unavailable")
        }
    }

    private fun fetch(latitude: Double, longitude: Double): JSONObject {
        val url = "https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude" +
            "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,cloud_cover" +
            "&daily=temperature_2m_max,temperature_2m_min" +
            "&hourly=temperature_2m,is_day,precipitation_probability&timeformat=unixtime&timezone=auto&forecast_days=2"
        val json = JSONObject(URL(url).openStream().use { it.readBytes().toString(Charsets.UTF_8) })
        val now = json.getJSONObject("current")
        val daily = json.optJSONObject("daily")
        val hourly = hours(json.optJSONObject("hourly") ?: JSONObject(), now.optDouble("time", 0.0))
        return JSONObject()
            .put("source", "open_meteo")
            .put("temperature", now.getDouble("temperature_2m"))
            .put("feels_like", now.optDouble("apparent_temperature"))
            .put("humidity", now.optDouble("relative_humidity_2m") / 100)
            .put("wind", now.optDouble("wind_speed_10m"))
            .put("high", daily?.optJSONArray("temperature_2m_max")?.optDouble(0))
            .put("low", daily?.optJSONArray("temperature_2m_min")?.optDouble(0))
            .put("condition", kind(now.optInt("weather_code", -1)))
            .put("cloud_cover", now.optDouble("cloud_cover", 0.0) / 100)
            .put("rain_soon", hourly.firstOrNull()?.optBoolean("rain") ?: false)
            .put("hourly", JSONArray(hourly.map { JSONObject(it.toString()).apply { remove("rain") } }))
            .put("attribution", JSONObject().put("name", "Open-Meteo.com").put("url", "https://open-meteo.com/"))
    }

    private fun hours(hourly: JSONObject, now: Double): List<JSONObject> {
        val times = hourly.optJSONArray("time") ?: JSONArray()
        val temperatures = hourly.optJSONArray("temperature_2m") ?: JSONArray()
        val days = hourly.optJSONArray("is_day") ?: JSONArray()
        val rain = hourly.optJSONArray("precipitation_probability") ?: JSONArray()
        val first = (0 until times.length()).firstOrNull { times.optDouble(it) > now - 3600 } ?: 0
        return (first until times.length()).take(25).filter { !temperatures.isNull(it) }.map { index ->
            JSONObject()
                .put("time", times.optDouble(index))
                .put("temperature", temperatures.optDouble(index))
                .put("daylight", days.optInt(index, 1) == 1)
                .put("rain", rain.optDouble(index, 0.0) >= 30)
        }
    }

    private fun kind(code: Int): String = when (code) {
        0 -> "clear"
        1, 2 -> "partly_cloudy"
        3 -> "cloudy"
        45, 48 -> "fog"
        in 51..57 -> "drizzle"
        in 61..67, in 80..82 -> "rain"
        in 71..77, 85, 86 -> "snow"
        in 95..99 -> "thunderstorm"
        else -> "unknown"
    }
}
