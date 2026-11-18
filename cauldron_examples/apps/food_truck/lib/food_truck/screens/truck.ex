defmodule FoodTruck.Screens.Truck do
  @moduledoc """
  The truck at a glance, as Food Truck opens: the brand header, then cards for the newest
  orders, the forecast where the truck is parked, the donuts on the menu and what is
  trending in the social feed, each heading opening its own screen. The cards sit two to
  a row when the detail beside the sidebar is 520 points or wider, one above another on a
  phone or in a narrower window.
  """

  import CauldronNative.UI

  alias FoodTruck.{Donut, Look, Order, Social, Store}

  @placeholder [
    63,
    68,
    72,
    77,
    80,
    82,
    83,
    83,
    81,
    79,
    75,
    70,
    66,
    64,
    63,
    61,
    60,
    59,
    57,
    56,
    55,
    55,
    56,
    59,
    62
  ]

  @doc "The Truck screen; `state` gives the weather and whether the newest order is new."
  @spec page(map()) :: CauldronNative.UI.Node.t()
  def page(state) do
    screen("Truck", [
      scroll(
        [
          vstack(
            [
              native(:brand_header, modifiers: [frame: [max_width: :infinity, height: 200]]),
              grid([orders(state), forecast(state.forecast), donuts(), social()],
                columns: columns(state.window),
                spacing: 12,
                modifiers: [padding: [horizontal: 16, bottom: 16], frame: [max_width: 1200]]
              )
            ],
            spacing: 16
          )
        ],
        modifiers: [background: :secondary_background]
      )
    ])
  end

  defp orders(state) do
    orders = Store.orders()
    newest = List.last(orders)

    panel([
      Look.card_heading("New Orders", [ios: "shippingbox", android: "Inventory2"], :orders),
      native(:order_tiles,
        orders:
          for order <- orders |> Enum.reverse() |> Enum.take(5) do
            %{number: order.number, donuts: Enum.map(Order.donut_ids(order), &donut_layers/1)}
          end,
        modifiers: [frame: [max_width: :infinity, max_height: 250]]
      ),
      newest && newest_order(newest, state.pulse)
    ])
  end

  defp newest_order(order, pulse?) do
    look = if pulse?, do: [bold: true], else: [foreground: :secondary]

    hstack(
      [
        spacer(),
        text(Order.title(order), modifiers: look),
        image({:asset, "donut"}, modifiers: [frame: [width: 18, height: 14]] ++ look),
        text(Look.number(Order.total(order)), modifiers: look),
        spacer()
      ],
      spacing: 6
    )
  end

  defp forecast(report) do
    panel([
      Look.card_heading(
        "Forecast",
        [ios: "cloud.sun", android: "WbCloudy"],
        {:city, :san_francisco}
      ),
      native(:forecast_chart,
        entries: forecast_entries(report),
        unit: "°F",
        modifiers: [frame: [min_height: 180]]
      )
    ])
  end

  defp forecast_entries(%{hourly: [_ | _] = hours}) do
    for hour <- hours,
        do: %{
          time: DateTime.to_unix(hour.time),
          degrees: Float.round(Look.fahrenheit(hour.temperature), 1),
          daylight: hour.daylight
        }
  end

  defp forecast_entries(_report) do
    start = DateTime.new!(~D[2022-05-06], ~T[09:00:00], "Etc/UTC") |> DateTime.to_unix()

    for {degrees, hour} <- Enum.with_index(@placeholder),
        do: %{time: start + hour * 3600, degrees: degrees, daylight: hour < 12 or hour > 20}
  end

  defp donuts do
    panel([
      Look.card_heading("Donuts", {:asset, "donut"}, :donuts),
      native(:donut_lattice,
        donuts: Store.donuts() |> Enum.take(14) |> Enum.map(&Donut.layers/1),
        modifiers: [frame: [max_width: :infinity, min_height: 180]]
      )
    ])
  end

  defp social do
    panel([
      Look.card_heading(
        "Social Feed",
        [ios: "text.bubble", android: "ChatBubbleOutline"],
        :social
      ),
      vstack(
        [
          Look.tags(Social.trending(), :center),
          text("Trending Topics", modifiers: [font: :footnote, foreground: :secondary])
        ],
        spacing: 8,
        modifiers: [padding: [top: 15], frame: [max_width: :infinity, min_height: 180]]
      )
    ])
  end

  defp panel(children) do
    vstack(children,
      alignment: :leading,
      modifiers: [
        padding: 10,
        frame: [max_width: :infinity, max_height: :infinity],
        background: :background,
        corner_radius: 12
      ]
    )
  end

  defp donut_layers(id), do: id |> Store.donut() |> Donut.layers()

  defp columns(%{compact: true}), do: 1
  defp columns(%{width: width}) when width < 760, do: 1
  defp columns(_window), do: 2
end
