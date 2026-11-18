defmodule CauldronNative.Weather do
  @moduledoc """
  The weather at a place, from Apple Weather (WeatherKit) on iOS, tvOS and macOS, and
  from Open-Meteo, a free service with no key, where WeatherKit is not there: on Android,
  and on an Apple device when the app lacks WeatherKit's capability or WeatherKit cannot
  answer.

  WeatherKit needs the app's config to name it (`weatherkit: true`, which adds its
  entitlement) and a paid Apple Developer Program team whose App ID has the WeatherKit
  capability; without them the app falls back to Open-Meteo by itself.

  The answer arrives as `CauldronNative.Device`'s do, `{:device, tag, answer}`, the
  weather a `CauldronNative.Weather.Report`:

      def handle_event(:refresh, _value, state) do
        CauldronNative.Weather.current(:here, {37.33, -122.03})
        state
      end

      def handle_info({:device, :here, {:ok, report}}, state), do: %{state | weather: report}
      def handle_info({:device, :here, {:error, :unavailable}}, state), do: state

  Show the report's `attribution` with its data: Apple requires WeatherKit's logo and
  legal link, and Open-Meteo's licence requires a credit.

  The error is `:unavailable`: neither service answered (no network, say).
  """

  alias CauldronNative.Device.Request

  @doc "The weather now and today at `{latitude, longitude}`, answered `{:ok, report}` once."
  @spec current(term(), {number(), number()}) :: :ok
  def current(tag, {latitude, longitude}),
    do: Request.send(tag, "weather", %{latitude: latitude, longitude: longitude})
end
