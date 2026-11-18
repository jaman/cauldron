defmodule FoodTruck.Store do
  @moduledoc """
  The truck's data, kept in one process: the menu's donuts, saved to a DETS file in the
  app's data folder (`CAULDRON_NATIVE_DATA`, or `~/.food_truck` off the device); today's
  orders and the cities' sales history, made by `FoodTruck.OrderGenerator` when the
  store starts; and 20 more orders that come in after it, 3 to 8 seconds apart.

  A process that `subscribe/0`s is sent `{:food_truck, :changed}` after each change.
  """

  use GenServer

  alias FoodTruck.{City, Donut, Flavor, Order, OrderGenerator}

  @type timeframe :: :today | :week | :month | :year
  @type sort :: :name | {:popularity, timeframe()} | {:flavor, Flavor.t()}

  @live_orders 20

  @doc "Start the store, registered under its module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Be sent `{:food_truck, :changed}` after each change."
  @spec subscribe() :: :ok
  def subscribe, do: GenServer.call(__MODULE__, {:subscribe, self()})

  @doc "The menu's donuts, by id."
  @spec donuts() :: [Donut.t()]
  def donuts, do: GenServer.call(__MODULE__, :donuts)

  @doc "The donut with `id`."
  @spec donut(Donut.id()) :: Donut.t() | nil
  def donut(id), do: Enum.find(donuts(), &(&1.id == id))

  @doc "The menu's donuts in the `sort` order."
  @spec donuts(sort()) :: [Donut.t()]
  def donuts(sort), do: GenServer.call(__MODULE__, {:donuts, sort})

  @doc "A new donut for the editor, with the id it gets once saved."
  @spec new_donut() :: Donut.t()
  def new_donut, do: GenServer.call(__MODULE__, :new_donut)

  @doc "Save `donut`, on the menu under its id."
  @spec save_donut(Donut.t()) :: Donut.t()
  def save_donut(%Donut{} = donut), do: GenServer.call(__MODULE__, {:save_donut, donut})

  @doc "Today's orders, oldest first."
  @spec orders() :: [Order.t()]
  def orders, do: GenServer.call(__MODULE__, :orders)

  @doc "The order numbered `number`."
  @spec order(pos_integer()) :: Order.t() | nil
  def order(number), do: Enum.find(orders(), &(&1.number == number))

  @doc "Take the order numbered `number` on a step (`FoodTruck.Order.next_step/2`)."
  @spec next_step(pos_integer()) :: Order.t()
  def next_step(number), do: GenServer.call(__MODULE__, {:change, number, &Order.next_step/2})

  @doc "Complete the order numbered `number`."
  @spec complete(pos_integer()) :: Order.t()
  def complete(number), do: GenServer.call(__MODULE__, {:change, number, &Order.complete/2})

  @doc "Each donut sold in `timeframe` and how many, the most sold first."
  @spec sales(timeframe()) :: [{Donut.t(), non_neg_integer()}]
  def sales(timeframe), do: GenServer.call(__MODULE__, {:sales, timeframe})

  @doc """
  Each city's donuts sold per day over the last two weeks (`:week`) or month (`:month`),
  or per month over the year (`:year`), as `{city, [{date, sold}]}`, the most recent
  first.
  """
  @spec history(:week | :month | :year) :: [{City.t(), [{Date.t(), non_neg_integer()}]}]
  def history(timeframe), do: GenServer.call(__MODULE__, {:history, timeframe})

  @impl GenServer
  def init(opts) do
    file = Keyword.get_lazy(opts, :file, &default_file/0)
    File.mkdir_p!(Path.dirname(file))
    {:ok, table} = :dets.open_file(__MODULE__, file: String.to_charlist(file))
    donuts = loaded(table)
    now = NaiveDateTime.local_now()
    today = NaiveDateTime.to_date(now)
    known = Donut.all()
    live = OrderGenerator.live()
    {wait, live} = OrderGenerator.seconds(live, 3, 8)
    Process.send_after(self(), :order, round(wait * 1000))

    {:ok,
     %{
       table: table,
       donuts: donuts,
       orders: OrderGenerator.today(known, now),
       daily: Map.new(City.all(), &{&1.id, OrderGenerator.daily(known, &1.id, today)}),
       monthly: Map.new(City.all(), &{&1.id, OrderGenerator.monthly(known, &1.id, today)}),
       live: live,
       coming: @live_orders,
       subscribers: MapSet.new()
     }}
  end

  @impl GenServer
  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  def handle_call(:donuts, _from, state), do: {:reply, state.donuts, state}

  def handle_call({:donuts, sort}, _from, state), do: {:reply, sorted(state, sort), state}

  def handle_call(:new_donut, _from, state), do: {:reply, Donut.new(next_id(state)), state}

  def handle_call({:save_donut, donut}, _from, state) do
    donuts =
      state.donuts
      |> Enum.reject(&(&1.id == donut.id))
      |> Kernel.++([donut])
      |> Enum.sort_by(& &1.id)

    :ok = :dets.insert(state.table, {:donuts, donuts})
    :ok = :dets.sync(state.table)
    {:reply, donut, changed(%{state | donuts: donuts})}
  end

  def handle_call(:orders, _from, state), do: {:reply, state.orders, state}

  def handle_call({:change, number, change}, _from, state) do
    now = NaiveDateTime.truncate(NaiveDateTime.local_now(), :second)

    orders =
      Enum.map(state.orders, &if(&1.number == number, do: change.(&1, now), else: &1))

    {:reply, Enum.find(orders, &(&1.number == number)), changed(%{state | orders: orders})}
  end

  def handle_call({:sales, timeframe}, _from, state) do
    sold = sold(state, timeframe)

    sales =
      state.donuts
      |> Enum.filter(&Map.has_key?(sold, &1.id))
      |> Enum.map(&{&1, sold[&1.id]})
      |> Enum.sort_by(fn {donut, count} -> {-count, donut.id} end)

    {:reply, sales, state}
  end

  def handle_call({:history, timeframe}, _from, state) do
    history =
      for city <- City.all() do
        summaries = history_summaries(state, city.id, timeframe)
        {city, for({date, sales} <- summaries, do: {date, Enum.sum(Map.values(sales))})}
      end

    {:reply, history, state}
  end

  @impl GenServer
  def handle_info(:order, %{coming: 0} = state), do: {:noreply, state}

  def handle_info(:order, state) do
    now = NaiveDateTime.local_now()
    number = length(state.orders) + 1
    {order, live} = OrderGenerator.order(Donut.all(), number, now, state.live)
    {wait, live} = OrderGenerator.seconds(live, 3, 8)
    if state.coming > 1, do: Process.send_after(self(), :order, round(wait * 1000))

    {:noreply,
     changed(%{state | orders: state.orders ++ [order], live: live, coming: state.coming - 1})}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}

  @impl GenServer
  def terminate(_reason, state), do: :dets.close(state.table)

  defp changed(state) do
    for pid <- state.subscribers, do: send(pid, {:food_truck, :changed})
    state
  end

  defp sorted(state, :name), do: Enum.sort_by(state.donuts, &String.downcase(&1.name))

  defp sorted(state, {:flavor, flavor}),
    do: Enum.sort_by(state.donuts, &{-Donut.flavors(&1)[flavor], &1.id})

  defp sorted(state, {:popularity, timeframe}) do
    sold = sold(state, timeframe)
    Enum.sort_by(state.donuts, &{-Map.get(sold, &1.id, -1), &1.id})
  end

  defp sold(state, :today) do
    for order <- state.orders, {id, count} <- order.sales, reduce: %{} do
      sold -> Map.update(sold, id, count, &(&1 + count))
    end
  end

  defp sold(state, timeframe) do
    for {_city, summaries} <- summaries(state, timeframe),
        {_date, sales} <- summaries,
        {id, count} <- sales,
        reduce: %{} do
      sold -> Map.update(sold, id, count, &(&1 + count))
    end
  end

  defp summaries(state, :week),
    do: Map.new(state.daily, fn {id, days} -> {id, Enum.take(days, 7)} end)

  defp summaries(state, :month),
    do: Map.new(state.daily, fn {id, days} -> {id, Enum.take(days, 30)} end)

  defp summaries(state, :year), do: state.monthly

  defp history_summaries(state, city, :week), do: Enum.take(state.daily[city], 14)
  defp history_summaries(state, city, :month), do: Enum.take(state.daily[city], 30)
  defp history_summaries(state, city, :year), do: state.monthly[city]

  defp next_id(state),
    do: state.donuts |> Enum.map(& &1.id) |> Enum.max(fn -> -1 end) |> Kernel.+(1)

  defp loaded(table) do
    case :dets.lookup(table, :donuts) do
      [{:donuts, donuts}] -> donuts
      [] -> Donut.all()
    end
  end

  defp default_file do
    folder =
      System.get_env("CAULDRON_NATIVE_DATA") || Path.join(System.user_home!(), ".food_truck")

    Path.join(folder, "food_truck_menu.dets")
  end
end
