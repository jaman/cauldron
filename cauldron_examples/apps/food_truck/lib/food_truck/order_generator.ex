defmodule FoodTruck.OrderGenerator do
  @moduledoc """
  The truck's simulated business, the same on every launch: today's orders up to a
  moment (`today/2`), a new order as it comes in (`order/4`), and each city's donut sales
  for the last 60 days (`daily/3`) and 13 months (`monthly/3`), most recent first, as
  `{date, %{donut_id => sold}}`.

  The most popular donut sells 80 to 120 a day, and each one after it fewer, falling off
  steeply; weekends sell a quarter more, and each day is pulled halfway towards the day
  before it (a month a quarter of the way).
  """

  alias FoodTruck.{Donut, Order}

  @falloff 0.15
  @cities %{cupertino: {0.5, 1}, san_francisco: {1.0, 2}, london: {0.75, 3}}

  @type summary :: {Date.t(), %{Donut.id() => non_neg_integer()}}

  @doc """
  Today's 24 orders up to `now`, oldest first, numbered from 1201: the newest nine still
  placed, the others ready.
  """
  @spec today([Donut.t()], NaiveDateTime.t()) :: [Order.t()]
  def today(donuts, now) do
    count = 24

    {orders, _random, _time} =
      Enum.reduce(0..(count - 1), {[], seed(1), NaiveDateTime.add(now, -4 * 60)}, fn index,
                                                                                     {orders,
                                                                                      random,
                                                                                      time} ->
        {gap, random} = between(random, 60, 180)
        time = NaiveDateTime.add(time, -round(gap))
        {order, random} = order(donuts, count - index, time, random)
        {[ready(order, index > 8, now) | orders], random, time}
      end)

    orders
  end

  @doc """
  The order numbered `1200 + number` placed `at`: one to five donuts of the menu, one to
  five of each, from the random state `random`; with the state after it.
  """
  @spec order([Donut.t()], pos_integer(), NaiveDateTime.t(), :rand.state()) ::
          {Order.t(), :rand.state()}
  def order(donuts, number, at, random) do
    {shuffled, random} = shuffle(donuts, random)
    {how_many, random} = integer(random, 1, 5)

    {sales, random} =
      shuffled
      |> Enum.take(how_many)
      |> Enum.map_reduce(random, fn donut, random ->
        {sold, random} = integer(random, 1, 5)
        {{donut.id, sold}, random}
      end)

    order = %Order{
      number: 1200 + number,
      status: :placed,
      sales: sales,
      created_at: NaiveDateTime.truncate(at, :second)
    }

    {order, random}
  end

  @doc "A random state for the orders that come in after launch."
  @spec live() :: :rand.state()
  def live, do: seed(5)

  @doc "A number of seconds between `low` and `high` from `random`, with the state after it."
  @spec seconds(:rand.state(), number(), number()) :: {float(), :rand.state()}
  def seconds(random, low, high), do: between(random, low, high)

  @doc "The city's sales on each of the 60 days before `today`, the most recent first."
  @spec daily([Donut.t()], atom(), Date.t()) :: [summary()]
  def daily(donuts, city, today) do
    {multiplier, seed} = Map.fetch!(@cities, city)
    {shuffled, random} = shuffle(donuts, seed(seed))

    60..1//-1
    |> Enum.map_reduce({random, nil}, fn days_ago, {random, previous} ->
      day = Date.add(today, -days_ago)
      weekend = if Date.day_of_week(day) in [6, 7], do: 1.25, else: 1.0
      {orders, random} = between(random, 80, 120)
      {sales, random} = sales(shuffled, length(donuts), orders, multiplier * weekend, random)
      sales = towards(sales, previous, 0.5)
      {{day, sales}, {random, sales}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc "The city's sales in each of the 13 months up to `today`'s, the most recent first."
  @spec monthly([Donut.t()], atom(), Date.t()) :: [summary()]
  def monthly(donuts, city, today) do
    {multiplier, seed} = Map.fetch!(@cities, city)
    {shuffled, random} = shuffle(donuts, seed(seed))
    first = Date.beginning_of_month(today)

    12..0//-1
    |> Enum.map_reduce({random, nil}, fn months_ago, {random, previous} ->
      {orders, random} = between(random, 80, 120)
      {sales, random} = sales(shuffled, length(donuts), orders * 30, multiplier, random)
      sales = towards(sales, previous, 0.25)
      {{Date.shift(first, month: -months_ago), sales}, {random, sales}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp ready(order, false, _now), do: order

  defp ready(order, true, now) do
    done = NaiveDateTime.add(order.created_at, 14 * 60)
    done = if NaiveDateTime.compare(done, now) == :gt, do: now, else: done
    %{order | status: :ready, completed_at: NaiveDateTime.truncate(done, :second)}
  end

  defp sales(shuffled, count, orders, multiplier, random) do
    {most, random} = between(random, 0.75, 1.1)
    most = orders * most

    shuffled
    |> Enum.with_index()
    |> Enum.map_reduce(random, fn {donut, place}, random ->
      share = 1 - :math.pow(place / count, @falloff)
      {variance, random} = between(random, 0.9, 1.0)
      {{donut.id, max(trunc(most * share * variance * multiplier), 0)}, random}
    end)
    |> then(fn {sales, random} -> {Map.new(sales), random} end)
  end

  defp towards(sales, nil, _share), do: sales

  defp towards(sales, previous, share),
    do: Map.new(sales, fn {id, sold} -> {id, trunc(sold + (previous[id] - sold) * share)} end)

  defp seed(seed), do: :rand.seed_s(:exsss, {seed, seed * 7, seed * 13})

  defp between(random, low, high) do
    {unit, random} = :rand.uniform_s(random)
    {low + (high - low) * unit, random}
  end

  defp integer(random, low, high) do
    {value, random} = :rand.uniform_s(high - low + 1, random)
    {low + value - 1, random}
  end

  defp shuffle(list, random) do
    {keyed, random} =
      Enum.map_reduce(list, random, fn item, random ->
        {key, random} = :rand.uniform_s(random)
        {{key, item}, random}
      end)

    {keyed |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)), random}
  end
end
