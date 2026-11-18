defmodule FoodTruck.Screens.City do
  @moduledoc """
  A city the truck parks in: its recommended parking spot shown on a map that turns
  slowly around it, the weather there, and notes for the season. The recommended spot is
  the first of the city's spots where rain is not coming soon (`recommend/2`).
  """

  import CauldronNative.UI

  alias FoodTruck.{City, Look}

  @doc """
  The city's screen with `found`, `%{spot: index, report: report}` (the spot recommended
  so far and its weather, `report` `nil` while on its way), or `nil` before any.
  """
  @spec page(atom(), map() | nil) :: CauldronNative.UI.Node.t()
  def page(id, found) do
    city = City.fetch!(id)
    spot = Enum.at(city.spots, (found && found.spot) || 0)
    report = found && found.report

    screen(city.name, [
      scroll([
        vstack(
          [
            zstack(
              [
                native(:spot_showcase,
                  latitude: elem(spot.at, 0),
                  longitude: elem(spot.at, 1),
                  distance: spot.camera,
                  modifiers: [frame: [max_width: :infinity, height: 350]]
                ),
                report && weather_card(report)
              ],
              alignment: :bottom_trailing
            ),
            vstack(
              [
                recommended(spot, report),
                vstack(
                  [
                    text("Cloud cover percentage is currently #{cloud(report)}% in #{city.name}"),
                    text("Popular donuts this season include Custard, Super Lemon, and Rainbow"),
                    text(
                      "Recommendation to stock up on cold ingredients and popular toppings to be prepared for the season"
                    )
                  ],
                  alignment: :leading,
                  spacing: 8,
                  modifiers: [
                    padding: 16,
                    frame: [max_width: :infinity],
                    background: :secondary_background,
                    corner_radius: 16
                  ]
                )
              ],
              spacing: 10,
              modifiers: [padding: 16]
            ),
            credit(report)
          ],
          spacing: 10,
          modifiers: [padding: [bottom: 16]]
        )
      ])
    ])
  end

  @doc """
  Whether to look further for a spot: given the city and the spot whose weather just
  came, the next spot's index while this one expects rain and another is left, else
  `nil`.
  """
  @spec recommend(atom(), non_neg_integer(), CauldronNative.Weather.Report.t()) ::
          non_neg_integer() | nil
  def recommend(id, spot, %{rain_soon: true}) do
    if spot + 1 < length(City.fetch!(id).spots), do: spot + 1
  end

  def recommend(_id, _spot, _report), do: nil

  defp weather_card(report) do
    hstack(
      [
        icon(:star,
          ios: report.ios_icon,
          android: report.android_icon,
          modifiers: [font: :title2, foreground: :secondary]
        ),
        vstack(
          [
            text(report.description, modifiers: [font: :headline]),
            text(if(report.rain_soon, do: "Will rain soon...", else: "No chance of rain today"),
              modifiers: [font: :subheadline, foreground: :secondary]
            )
          ],
          alignment: :leading
        )
      ],
      modifiers: [
        padding: 16,
        background: :background,
        opacity: 0.92,
        corner_radius: 12,
        frame: [max_width: 400],
        padding: 16
      ]
    )
  end

  defp recommended(spot, report) do
    temperature =
      if report, do: "#{round(Look.fahrenheit(report.temperature))}°F", else: "72°F"

    hstack(
      [
        vstack(
          [
            text("Recommended",
              modifiers: [font: :subheadline, foreground: :secondary, opacity: 0.7]
            ),
            text(spot.name),
            text("Parking Spot", modifiers: [font: :caption, foreground: :secondary])
          ],
          alignment: :leading
        ),
        spacer(),
        summary(temperature,
          ios: (report && report.ios_icon) || "sun.max",
          android: (report && report.android_icon) || "WbSunny"
        ),
        summary("Popular", ios: "person.3", android: "Groups"),
        summary("Trending", ios: "chart.line.uptrend.xyaxis", android: "TrendingUp")
      ],
      modifiers: [
        padding: 16,
        frame: [max_width: :infinity],
        background: :secondary_background,
        corner_radius: 20
      ]
    )
  end

  defp summary(title, icons) do
    vstack(
      [
        icon(
          :star,
          icons ++
            [modifiers: [font: :title3, foreground: :secondary, frame: [width: 30, height: 30]]]
        ),
        text(title, modifiers: [font: :footnote, foreground: :secondary])
      ],
      spacing: 2
    )
  end

  defp cloud(%{cloud_cover: cover}) when is_number(cover), do: round(cover * 100)
  defp cloud(_report), do: 0

  defp credit(%{source: :weatherkit, attribution: attribution}) do
    vstack(
      [
        image(attribution.logo_light, modifiers: [frame: [width: 20, height: 20]]),
        link("Other data sources", attribution.url)
      ],
      modifiers: [font: :footnote]
    )
  end

  defp credit(%{attribution: attribution}),
    do: link("Weather data by #{attribution.name}", attribution.url, modifiers: [font: :footnote])

  defp credit(nil),
    do:
      link("Other data sources", "https://weather-data.apple.com/legal-attribution.html",
        modifiers: [font: :footnote]
      )
end
