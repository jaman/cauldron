defmodule CauldronNative.Weather.Report do
  @moduledoc """
  The weather at one place now and over today: temperatures in °C, `humidity` from 0.0 to
  1.0, `wind` in km/h, the `condition` as one of a few kinds, the platform's words for it
  (`description`), the icons to show it with (`ios_icon`, an SF Symbol; `android_icon`, a
  Material icon), the share of the sky in cloud (`cloud_cover`, 0.0 to 1.0), whether rain
  is likely within the hour (`rain_soon`, a 30% chance or more), the next 25 hours
  (`hourly`, each `%{time, temperature, daylight}`, `time` a UTC `DateTime` on the hour
  and `daylight` whether the sun is up), which service it came from, and the attribution
  that service requires the app to show.

  `source` is `:weatherkit` (Apple Weather) or `:open_meteo`. `attribution` is `%{name,
  url, logo_light, logo_dark}`: WeatherKit's service name, legal page and logos, which
  Apple requires an app to show beside its data, or Open-Meteo's name and page (its data
  is CC BY 4.0, so the app credits it), with no logos.
  """

  @enforce_keys [:temperature, :condition, :source]
  defstruct [
    :temperature,
    :feels_like,
    :humidity,
    :wind,
    :high,
    :low,
    :condition,
    :description,
    :ios_icon,
    :android_icon,
    :source,
    cloud_cover: nil,
    rain_soon: false,
    hourly: [],
    attribution: %{name: nil, url: nil, logo_light: nil, logo_dark: nil}
  ]

  @type condition ::
          :clear
          | :partly_cloudy
          | :cloudy
          | :fog
          | :drizzle
          | :rain
          | :snow
          | :thunderstorm
          | :unknown
  @type t :: %__MODULE__{
          temperature: float(),
          feels_like: float() | nil,
          humidity: float() | nil,
          wind: float() | nil,
          high: float() | nil,
          low: float() | nil,
          condition: condition(),
          description: String.t(),
          ios_icon: String.t(),
          android_icon: String.t(),
          source: :weatherkit | :open_meteo,
          cloud_cover: float() | nil,
          rain_soon: boolean(),
          hourly: [%{time: DateTime.t(), temperature: float(), daylight: boolean()}],
          attribution: %{
            name: String.t() | nil,
            url: String.t() | nil,
            logo_light: String.t() | nil,
            logo_dark: String.t() | nil
          }
        }

  @conditions %{
    "clear" => {:clear, "Clear", "sun.max", "WbSunny"},
    "partly_cloudy" => {:partly_cloudy, "Partly Cloudy", "cloud.sun", "WbCloudy"},
    "cloudy" => {:cloudy, "Cloudy", "cloud", "Cloud"},
    "fog" => {:fog, "Fog", "cloud.fog", "Foggy"},
    "drizzle" => {:drizzle, "Drizzle", "cloud.drizzle", "Grain"},
    "rain" => {:rain, "Rain", "cloud.rain", "Umbrella"},
    "snow" => {:snow, "Snow", "cloud.snow", "AcUnit"},
    "thunderstorm" => {:thunderstorm, "Thunderstorms", "cloud.bolt.rain", "Thunderstorm"}
  }

  @doc """
  The report in the platform's answer: `condition` one of the kinds' names; `symbol` and
  `description`, WeatherKit's own, taking the place of the kind's.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    {condition, description, symbol, material} =
      Map.get(
        @conditions,
        json["condition"],
        {:unknown, "Unknown", "questionmark", "HelpOutline"}
      )

    attribution = json["attribution"] || %{}

    %__MODULE__{
      temperature: json["temperature"],
      feels_like: json["feels_like"],
      humidity: json["humidity"],
      wind: json["wind"],
      high: json["high"],
      low: json["low"],
      condition: condition,
      description: json["description"] || description,
      ios_icon: json["symbol"] || symbol,
      android_icon: material,
      source: if(json["source"] == "weatherkit", do: :weatherkit, else: :open_meteo),
      cloud_cover: json["cloud_cover"],
      rain_soon: json["rain_soon"] == true,
      hourly: Enum.map(json["hourly"] || [], &hour/1),
      attribution: %{
        name: attribution["name"],
        url: attribution["url"],
        logo_light: attribution["logo_light"],
        logo_dark: attribution["logo_dark"]
      }
    }
  end

  defp hour(json),
    do: %{
      time: DateTime.from_unix!(round(json["time"])),
      temperature: json["temperature"],
      daylight: json["daylight"] != false
    }
end
