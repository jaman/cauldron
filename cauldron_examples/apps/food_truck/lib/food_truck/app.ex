defmodule FoodTruck.App do
  @moduledoc """
  Food Truck, after Apple's SwiftUI sample of the same name
  (https://github.com/apple/sample-food-truck): a donut truck's orders, what people post
  about it, the account, its sales history, its donuts with an editor and the Top 5, and
  the cities it parks in with their weather (`CauldronNative.Weather`: Apple Weather where
  the app has WeatherKit, Open-Meteo otherwise). Social Feed+ and a year of sales history
  are sold in the app (`FoodTruck.Shop`); an order's Live Activity and the widgets show
  the truck outside it (`FoodTruck.AtAGlance`).

  The sidebar lists the truck's places, as the sample's does; on an iPad, a Mac or a wide
  Android screen it sits beside the chosen place, and on a phone it is the first screen.
  Each place is a stack of screens: an order opens from the orders, a donut's editor from
  the gallery, and on a phone each Truck card's screen from its heading.

  Launched with `FOOD_TRUCK_OPEN` set to a place (`orders`, `social`, `account`,
  `sales_history`, `donuts`, `donut_editor`, `top_five`, `city:london`), an order
  (`order:1203`) or a donut (`donut:3`), the app opens there, as it does for a
  `foodtruck://open/<place>` link; a `foodtruck://order/1203` link, which an order's Live
  Activity opens, opens the order.
  """

  use CauldronNative.App

  alias CauldronNative.{Device, Weather}
  alias FoodTruck.{AtAGlance, City, Order, Shop, Store}
  alias FoodTruck.Screens.{Account, Donuts, Orders, Sales, Social, Truck}
  alias FoodTruck.Screens.City, as: CityScreen

  @truck_spot {37.3348, -122.0090}

  @impl true
  def mount(_params) do
    system = Device.system()
    if system, do: outside()
    Store.subscribe()

    state = %{
      panel: :truck,
      pushed: [],
      window: %{width: 0, height: 0, compact: system == :ios, mac?: system == :macos},
      search: "",
      donut_search: "",
      selected: nil,
      completed: nil,
      draft: Store.new_donut(),
      top_timeframe: :week,
      history_timeframe: :week,
      gallery: %{layout: :grid, sort: :popularity, timeframe: :week, flavor: :sweet},
      forecast: nil,
      cities: %{},
      shop: Shop.new(),
      plus_settings: %{highlight: false, advanced: true},
      account: %{user: :default, confirming?: false, form: blank_form()},
      pulse: false,
      seen_orders: length(Store.orders()),
      started_at: NaiveDateTime.truncate(NaiveDateTime.local_now(), :second)
    }

    opened(state, System.get_env("FOOD_TRUCK_OPEN"))
  end

  @impl true
  def render(state) do
    theme(
      [
        split(sidebar(), [navigation([main(state) | pushed(state)], on_back: :back)],
          title: "Food Truck",
          selected: state.panel,
          on_select: :panel
        ),
        Orders.completed(state.completed),
        menu_bar_extra(
          "Food Truck",
          [
            native(:brand_header,
              reduced: true,
              still: true,
              modifiers: [frame: [max_width: :infinity, height: 100]]
            ),
            text("Donut stuff!", modifiers: [padding: 8])
          ],
          icon: :home,
          ios: "box.truck"
        )
      ],
      accent: "#5856D6",
      dynamic_color: false
    )
  end

  @impl true
  def handle_info({:food_truck, :changed}, state) do
    count = length(Store.orders())
    if Device.system(), do: AtAGlance.show_orders()

    if count > state.seen_orders do
      Process.send_after(self(), :pulse_off, 1_100)
      %{state | pulse: true, seen_orders: count}
    else
      state
    end
  end

  def handle_info(:pulse_off, state), do: %{state | pulse: false}
  def handle_info(:review, state), do: tap(state, fn _ -> Device.request_review() end)

  def handle_info({:cauldron_native, :window, window}, state),
    do: %{state | window: Map.merge(state.window, window)}

  def handle_info({:cauldron_native, :url, "foodtruck://order/" <> number}, state),
    do: open_order(%{state | panel: :truck, pushed: [:orders]}, String.to_integer(number))

  def handle_info({:cauldron_native, :url, "foodtruck://open/" <> place}, state),
    do: opened(%{state | panel: :truck, pushed: []}, URI.decode(place))

  def handle_info({:device, :forecast, {:ok, report}}, state), do: %{state | forecast: report}

  def handle_info({:device, {:spot, city, spot}, {:ok, report}}, state) do
    case CityScreen.recommend(city, spot, report) do
      nil -> put_in(state, [:cities, city], %{spot: spot, report: report})
      next -> tap(state, fn _ -> ask_spot(city, next) end)
    end
  end

  def handle_info({:device, {:shop, tag}, answer}, state),
    do: %{state | shop: Shop.answered(state.shop, tag, answer)}

  def handle_info(_message, state), do: state

  @impl true
  def handle_event(:panel, panel, state) do
    if match?({:city, _}, panel), do: ask_city(panel, state)
    %{state | panel: panel, pushed: [], search: "", selected: nil}
  end

  def handle_event(:back, keep, state), do: %{state | pushed: Enum.take(state.pushed, keep - 1)}

  def handle_event({:card, panel}, _value, %{window: %{compact: true}} = state) do
    if match?({:city, _}, panel), do: ask_city(panel, state)
    %{state | pushed: state.pushed ++ [panel]}
  end

  def handle_event({:card, panel}, _value, state), do: handle_event(:panel, panel, state)

  def handle_event(:search, text, state), do: %{state | search: text}
  def handle_event(:donut_search, text, state), do: %{state | donut_search: text}
  def handle_event(:select_order, number, state), do: %{state | selected: number}
  def handle_event({:open_order, nil}, _value, state), do: state
  def handle_event({:open_order, number}, _value, state), do: open_order(state, number)

  def handle_event({:complete_order, nil}, _value, state), do: state

  def handle_event({:complete_order, number}, _value, state) do
    order = Store.complete(number)
    if Device.system(), do: AtAGlance.follow(order)
    completed(state, number)
  end

  def handle_event({:next_step, number}, _value, state) do
    order = Store.next_step(number)
    if Device.system(), do: AtAGlance.follow(order)
    if Order.complete?(order), do: completed(state, number), else: state
  end

  def handle_event(:close_completed, _value, state), do: %{state | completed: nil}

  def handle_event(:new_donut, _value, state), do: %{state | pushed: state.pushed ++ [:new_donut]}

  def handle_event({:edit_donut, id}, _value, state),
    do: %{state | pushed: state.pushed ++ [{:donut, id}]}

  def handle_event({:donut_field, field}, value, state), do: edited(state, field, value)

  def handle_event(:top_timeframe, timeframe, state), do: %{state | top_timeframe: timeframe}

  def handle_event(:history_timeframe, timeframe, state),
    do: %{state | history_timeframe: timeframe}

  def handle_event({:gallery, option, value}, _value, state),
    do: %{state | gallery: Map.put(state.gallery, option, value)}

  def handle_event({:shop, action}, value, state),
    do: %{state | shop: Shop.event(state.shop, action, value)}

  def handle_event({:shop, action, argument}, _value, state),
    do: %{state | shop: Shop.event(state.shop, action, argument)}

  def handle_event({:plus_setting, key}, value, state),
    do: %{state | plus_settings: Map.put(state.plus_settings, key, value)}

  def handle_event(:account_support, _value, state),
    do: %{state | pushed: state.pushed ++ [:account_support]}

  def handle_event({:account, action}, _value, state),
    do: %{state | account: account(state.account, action)}

  def handle_event({:account_field, field}, value, state),
    do: put_in(state, [:account, :form, field], value)

  defp outside do
    Weather.current(:forecast, @truck_spot)
    Shop.ask()
    AtAGlance.show_all()
  end

  defp ask_city({:city, id}, state) do
    unless Map.has_key?(state.cities, id), do: ask_spot(id, 0)
  end

  defp ask_spot(city, spot) do
    if Device.system(),
      do: Weather.current({:spot, city, spot}, Enum.at(City.fetch!(city).spots, spot).at)
  end

  defp open_order(state, number), do: %{state | pushed: state.pushed ++ [{:order, number}]}

  defp completed(state, number) do
    Process.send_after(self(), :review, 2_250)
    %{state | completed: number}
  end

  defp edited(%{pushed: pushed} = state, field, value) do
    case List.last(pushed) do
      {:donut, id} ->
        tap(state, fn _ -> Store.save_donut(Map.put(Store.donut(id), field, value)) end)

      _draft ->
        %{state | draft: Map.put(state.draft, field, value)}
    end
  end

  defp account(account, :sign_in),
    do: %{account | form: %{blank_form() | open?: true, mode: :sign_in}}

  defp account(account, :sign_up),
    do: %{account | form: %{blank_form() | open?: true, mode: :sign_up}}

  defp account(account, :cancel), do: %{account | form: blank_form()}

  defp account(account, :submit),
    do: %{account | user: {:signed_in, account.form.name}, form: blank_form()}

  defp account(account, :confirm_sign_out), do: %{account | confirming?: true}
  defp account(account, :keep), do: %{account | confirming?: false}
  defp account(account, :sign_out), do: %{account | user: nil, confirming?: false}

  defp blank_form, do: %{open?: false, mode: :sign_up, name: "", password: ""}

  defp opened(state, "order:" <> number),
    do: open_order(%{state | panel: :orders}, String.to_integer(number))

  defp opened(state, "donut:" <> id),
    do: handle_event({:edit_donut, String.to_integer(id)}, nil, %{state | panel: :donuts})

  defp opened(state, "city:" <> id),
    do: handle_event(:panel, {:city, String.to_existing_atom(id)}, state)

  defp opened(state, panel)
       when panel in ~w(orders social account sales_history donuts donut_editor top_five),
       do: %{state | panel: String.to_existing_atom(panel)}

  defp opened(state, _nothing), do: state

  defp sidebar do
    [
      label("Truck", icon: :home, ios: "box.truck", android: "LocalShipping", id: :truck),
      label("Orders", icon: :list, ios: "shippingbox", android: "Inventory2", id: :orders),
      label("Social Feed",
        icon: :person,
        ios: "text.bubble",
        android: "ChatBubbleOutline",
        id: :social
      ),
      label("Account",
        icon: :account,
        ios: "person.crop.circle",
        android: "AccountCircle",
        id: :account
      ),
      label("Sales History",
        icon: :calendar,
        ios: "clock",
        android: "Schedule",
        id: :sales_history
      ),
      section("Donuts", [
        label("Donuts", asset: "donut", id: :donuts),
        label("Donut Editor",
          icon: :edit,
          ios: "slider.horizontal.3",
          android: "Tune",
          id: :donut_editor
        ),
        label("Top 5", icon: :star, ios: "trophy", android: "EmojiEvents", id: :top_five)
      ]),
      section(
        "Cities",
        for city <- City.all() do
          label(city.name,
            icon: :location,
            ios: "building.2",
            android: "LocationCity",
            id: {:city, city.id}
          )
        end
      )
    ]
  end

  defp main(%{panel: panel} = state), do: screen_for(panel, state)

  defp pushed(state), do: Enum.map(state.pushed, &screen_for(&1, state))

  defp screen_for(:truck, state), do: Truck.page(state)
  defp screen_for(:orders, state), do: Orders.page(state)
  defp screen_for(:social, state), do: Social.page(state)
  defp screen_for(:account, state), do: Account.page(state)
  defp screen_for(:account_support, _state), do: Account.support()
  defp screen_for(:sales_history, state), do: Sales.history(state)
  defp screen_for(:donuts, state), do: Donuts.gallery(state)
  defp screen_for(:donut_editor, state), do: Donuts.editor(state.draft, state.window)
  defp screen_for(:new_donut, state), do: Donuts.editor(state.draft, state.window)
  defp screen_for(:top_five, state), do: Sales.top_five(state)
  defp screen_for({:city, id}, state), do: CityScreen.page(id, state.cities[id])
  defp screen_for({:order, number}, _state), do: Orders.order(number)

  defp screen_for({:donut, id}, state),
    do: Donuts.editor(Store.donut(id) || state.draft, state.window)
end
