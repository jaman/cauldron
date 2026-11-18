defmodule FoodTruck.Screens.Sales do
  @moduledoc """
  What sells: the Top 5 donuts of the day, week, month or year, charted with their
  pictures, and the sales history of each city over two weeks, a month or a year, the
  last two shown to those who unlocked a year of history (`FoodTruck.Shop`).
  """

  import CauldronNative.UI

  alias FoodTruck.{Donut, Look, Shop, Store}

  @timeframes [today: "Day", week: "Week", month: "Month", year: "Year"]
  @history [week: "2 Weeks", month: "Month", year: "Year"]

  @doc "The Top 5 screen for `state.top_timeframe`."
  @spec top_five(map()) :: CauldronNative.UI.Node.t()
  def top_five(state) do
    top = state.top_timeframe |> Store.sales() |> Enum.take(5)

    screen("Top 5 Donuts", [
      scroll([
        vstack(
          [
            picker("Timeframe", @timeframes,
              value: state.top_timeframe,
              style: :segmented,
              on_change: :top_timeframe,
              modifiers: [padding: [bottom: 10]]
            ),
            native(:top_sales_chart,
              sales:
                for(
                  {donut, sold} <- top,
                  do: %{name: donut.name, layers: Donut.layers(donut), sales: sold}
                )
            )
          ],
          alignment: :leading,
          modifiers: [padding: 16]
        )
      ])
    ])
  end

  @doc "The Sales History screen for `state.history_timeframe`."
  @spec history(map()) :: CauldronNative.UI.Node.t()
  def history(state) do
    unlocked? = Shop.history_unlocked?(state.shop)
    timeframe = state.history_timeframe
    cities = Store.history(timeframe)
    total = Enum.sum(for {_city, days} <- cities, {_date, sold} <- days, do: sold)

    screen("Sales History", [
      scroll([
        vstack([
          vstack(
            [
              picker("Timeframe", @history,
                value: timeframe,
                style: :segmented,
                on_change: :history_timeframe,
                modifiers: [padding: [bottom: 10]]
              ),
              text("Total Sales", modifiers: [font: :subheadline, foreground: :secondary]),
              text("#{Look.number(total)} Donuts", modifiers: [font: :headline]),
              native(:sales_history_chart,
                cities:
                  for {city, days} <- cities do
                    %{name: city.name, entries: for({date, sold} <- days, do: [unix(date), sold])}
                  end,
                locked: timeframe != :week and not unlocked?,
                modifiers: [frame: [min_height: 300]]
              )
            ],
            alignment: :leading,
            modifiers: [padding: 16]
          ),
          unlock(state.shop, unlocked?)
        ])
      ])
    ])
  end

  defp unlock(_shop, true), do: nil

  defp unlock(shop, false) do
    case Shop.history_product(shop) do
      nil ->
        nil

      product ->
        native(:unlock_feature,
          name: product.name,
          price: product.price,
          expanded: shop.unlock_expanded?,
          on_unlock: {:shop, :unlock_history},
          on_collapse: {:shop, :collapse_unlock},
          on_expand: {:shop, :expand_unlock}
        )
    end
  end

  defp unix(%Date{} = date), do: date |> DateTime.new!(~T[12:00:00]) |> DateTime.to_unix()
end
