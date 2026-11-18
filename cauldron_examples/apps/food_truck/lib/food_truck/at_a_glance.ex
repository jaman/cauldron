defmodule FoodTruck.AtAGlance do
  @moduledoc """
  The truck outside the app, as Apple's sample shows it: an order's Live Activity
  (`CauldronNative.LiveActivity`), which counts down the 60 seconds an order takes to
  prepare and ends when the order is completed, with a notification when the donuts are
  done; and the widgets (`CauldronNative.Widget`): Orders, today's fulfilled orders
  against the day's quota on the Home and Lock Screens; Daily Donut, a different donut
  each hour with how it sold this week; and Parking Spot, where the truck is parked, on
  the Lock Screen.
  """

  import CauldronNative.UI

  alias CauldronNative.{LiveActivity, Notifications, Widget}
  alias FoodTruck.{City, Donut, Look, Order, Store}

  @preparation 60
  @quota 25
  @accent [{:asset, "AccentColorDimmed"}, {:asset, "AccentColor"}]
  @indigo [{:asset, "IslandBadge"}, {:asset, "AccentColorDimmed"}]

  @doc "Show every widget its content now."
  @spec show_all() :: :ok
  def show_all do
    show_orders()
    show_daily_donuts()
    show_parking_spot()
  end

  @doc "Show today's fulfilled orders against the day's quota in the Orders widget."
  @spec show_orders() :: :ok
  def show_orders do
    done = Enum.count(Store.orders(), &(&1.status in [:ready, :completed]))
    classic = Store.donut(0) || hd(Donut.all())

    Widget.update(:orders, %{
      small:
        vstack(
          [
            text("Orders", modifiers: [font: :title]),
            text("#{done} out of #{@quota}"),
            gauge(min(done, @quota),
              max: @quota,
              image: Enum.map(Donut.layers(classic), &{:asset, &1 <> "-thumb"}),
              modifiers: [tint: "white"]
            )
          ],
          alignment: :leading,
          modifiers: [foreground: "white", gradient: @accent, frame: [max_width: :infinity]]
        ),
      circular:
        gauge(min(done, @quota),
          max: @quota,
          style: :circular,
          current: "#{done}",
          modifiers: [tint: {:asset, "AccentColor"}]
        ),
      rectangular:
        vstack(
          [
            label("Orders",
              asset: "donut",
              modifiers: [font: :headline, foreground: {:asset, "AccentColor"}]
            ),
            gauge(min(done, @quota),
              max: @quota,
              style: :segmented,
              title: "#{done} out of #{@quota}",
              modifiers: [tint: {:asset, "AccentColor"}]
            )
          ],
          alignment: :leading,
          modifiers: [frame: [max_width: :infinity]]
        ),
      inline: label("#{done} of #{@quota} Orders", asset: "donut")
    })
  end

  @doc "Show the next five hours' donuts in the Daily Donut widget, one an hour."
  @spec show_daily_donuts() :: :ok
  def show_daily_donuts do
    donuts = Store.donuts()
    sold = Map.new(Store.sales(:week), fn {donut, count} -> {donut.id, count} end)
    hour = DateTime.utc_now() |> DateTime.truncate(:second) |> Map.merge(%{minute: 0, second: 0})

    Widget.timeline(
      :daily_donut,
      for offset <- 0..4 do
        donut = Enum.at(donuts, rem(hour.hour + offset, length(donuts)))
        {DateTime.add(hour, offset * 3600), daily_donut(donut, Map.get(sold, donut.id, 0))}
      end
    )
  end

  defp daily_donut(donut, sold) do
    picture =
      vstack(
        [
          zstack(for(layer <- Donut.layers(donut), do: image({:asset, layer <> "-thumb"}))),
          text(donut.name, modifiers: [font: :headline])
        ],
        alignment: :center
      )

    trend =
      vstack(
        [
          text("This week", modifiers: [font: :caption]),
          text("#{Look.number(sold)} sold", modifiers: [font: :title2, bold: true])
        ],
        alignment: :leading
      )

    look = [
      foreground: "white",
      gradient: @indigo,
      frame: [max_width: :infinity, max_height: :infinity]
    ]

    %{
      small: vstack([picture], modifiers: look),
      default: hstack([picture, trend], spacing: 16, modifiers: look)
    }
  end

  @doc "Show where the truck is parked in the Parking Spot widget."
  @spec show_parking_spot() :: :ok
  def show_parking_spot do
    city = City.fetch!(:cupertino)
    spot = hd(city.spots)
    truck = [icon: :home, ios: "box.truck", android: "LocalShipping"]

    Widget.update(:parking_spot, %{
      inline: label(spot.name, truck),
      circular:
        vstack([icon(:home, Keyword.delete(truck, :icon)), text("CUP")], alignment: :center),
      rectangular:
        hstack(
          [
            icon(:home, Keyword.delete(truck, :icon)),
            vstack(
              [
                text("Parking Spot", modifiers: [font: :headline]),
                text(spot.name),
                text(city.name, modifiers: [foreground: :secondary])
              ],
              alignment: :leading,
              spacing: 0
            )
          ],
          alignment: :top
        )
    })
  end

  @doc "Follow `order` outside the app now that it reached its status."
  @spec follow(Order.t()) :: :ok
  def follow(%Order{status: :preparing} = order) do
    ends = DateTime.add(DateTime.utc_now(), @preparation)
    LiveActivity.start({:order, order.number}, activity(order, ends))

    Notifications.schedule(
      {:done, order.number},
      "Donuts are done!",
      "Time to take them out of the oven.",
      after: @preparation
    )
  end

  def follow(%Order{status: :completed} = order) do
    Notifications.cancel({:done, order.number})
    LiveActivity.finish({:order, order.number}, activity(order, DateTime.utc_now()))
  end

  def follow(_order), do: :ok

  defp activity(order, ends) do
    %{
      title: "Order ##{order.number}",
      detail: "#{Order.total(order)} donuts",
      ends_at: ends,
      ends_label: "Remaining",
      image: "IslandExpandedIcon",
      compact_image: "IslandCompactIcon",
      background: "LiveActivityBackground",
      tint: "LightIndigo",
      badge: "IslandBadge",
      url: "foodtruck://order/#{order.number}",
      ios_icon: "box.truck",
      android_icon: "LocalShipping"
    }
  end
end
