defmodule CisternComplete.Brain do
  @moduledoc """
  A computer keeper for `Cauldron.Robot`. In order, it steps out of a flickering
  column, keeps clear of falling hail, runs to the grate and pours when its jars are
  nearly full or the storm has gone quiet with water in them, and otherwise walks under
  the lowest drop of rain.
  """

  @behaviour Cauldron.Robot

  alias CisternComplete.Yoke

  @dead_zone 0.2
  @grate 8.0

  @impl true
  def init(_opts), do: nil

  @impl true
  def decide(%{me: nil}, memory, _clock), do: {nil, memory}

  def decide(%{me: me, capacity: capacity}, memory, _clock) do
    {target, pour?} = goal(me, capacity)
    {%{held: held(me.yoke.centre, target, pour?), aim: nil}, memory}
  end

  @impl true
  def gone?(%{me: me}), do: me == nil or me.out?

  defp goal(%{strike: %{x: x}} = me, _capacity) when abs(x - me.yoke.centre) < 1.5,
    do: {if(x > me.yoke.centre, do: x - 3, else: x + 3), false}

  defp goal(me, capacity) do
    hail = Enum.filter(me.drops, &(&1.kind == :hail and &1.y > 6))
    rain = Enum.filter(me.drops, &(&1.kind == :rain))

    cond do
      Enum.any?(hail, &(abs(&1.x - me.yoke.centre) < 1.6)) -> {dodge(me, hail), false}
      pour_now?(me, rain, capacity) -> {@grate, true}
      rain != [] -> {Enum.max_by(rain, & &1.y).x, false}
      true -> {me.squall.x, false}
    end
  end

  defp pour_now?(me, rain, capacity) do
    water = Yoke.water(me.yoke)
    room = Yoke.count(me.yoke) * capacity - water
    water > 0 and (room <= 2 or rain == [])
  end

  defp dodge(me, hail) do
    nearest = Enum.min_by(hail, &abs(&1.x - me.yoke.centre))
    if nearest.x >= me.yoke.centre, do: nearest.x - 2.5, else: nearest.x + 2.5
  end

  defp held(centre, target, pour?) do
    walking =
      cond do
        target < centre - @dead_zone -> [:left]
        target > centre + @dead_zone -> [:right]
        true -> []
      end

    MapSet.new(if pour? and walking == [], do: [:pour], else: walking)
  end
end
