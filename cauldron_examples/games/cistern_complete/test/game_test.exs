defmodule CisternComplete.GameTest do
  use ExUnit.Case, async: true

  alias Cauldron.Test, as: World
  alias CisternComplete.{Field, Game, Tuning, Yoke}

  @tuning Tuning.new()
  @dt 1 / 30

  defp field(changes) do
    :alice
    |> Field.new("alice", 1, @tuning)
    |> Map.merge(%{lull: 0.0, until_drop: 5.0, until_strike: 99.0})
    |> Map.merge(Map.new(changes))
  end

  defp yoke(fills, centre \\ 8.0), do: %Yoke{centre: centre, jars: fills}

  defp steps(field, count) do
    Enum.reduce(1..count, {field, []}, fn _tick, {f, events} ->
      {stepped, new} = Field.step(f, @dt, @tuning)
      {stepped, events ++ new}
    end)
  end

  test "rain fills the jar it falls into" do
    {caught, _events} = Field.step(field(drops: [%{x: 8.0, y: 7.8, kind: :rain}]), @dt, @tuning)
    assert caught.yoke.jars.head == 1
    assert caught.drops == []
  end

  test "rain into a full jar spills, and that is a miss" do
    full = yoke(%{left: 0, head: 5, right: 0})

    {spilled, events} =
      Field.step(
        field(yoke: full, drops: [%{x: 8.0, y: 7.8, kind: :rain}], level: 2),
        @dt,
        @tuning
      )

    assert Enum.any?(events, &match?({:spill, _}, &1))
    assert Yoke.count(spilled.yoke) == 2
    assert spilled.level == 1
  end

  test "hail in a jar breaks it, and the storm goes on" do
    {cracked, events} =
      Field.step(field(drops: [%{x: 8.0, y: 7.8, kind: :hail}], level: 3), @dt, @tuning)

    refute Map.has_key?(cracked.yoke.jars, :head)
    assert cracked.level == 3
    assert Enum.any?(events, &match?({:crack, _}, &1))
  end

  test "a pour over the grate empties the jars into the cistern, doubled when all were full" do
    full = yoke(%{left: 5, head: 5, right: 5})
    start = field(yoke: full, level: 2, held: MapSet.new([:pour]))
    {pouring, _events} = Field.step(start, @dt, @tuning)
    {poured, events} = steps(pouring, 30)

    assert Yoke.water(poured.yoke) == 0
    assert poured.water == 15
    assert poured.score == 15 * 2 * 2
    assert {:gust, :alice} in events
  end

  test "lightning strikes a keeper still under it" do
    struck = field(level: 4, strike: %{x: 8.2, left: 0.01})
    {after_strike, events} = Field.step(struck, @dt, @tuning)

    assert Yoke.count(after_strike.yoke) == 2
    assert Enum.any?(events, &match?({:thunder, _}, &1))
  end

  test "a gust from one keeper's pour reaches every other keeper's Squall" do
    {:ok, driver} =
      Game |> World.new(game_opts: [seed: 3], hz: 30) |> World.join(:alice, %{username: "alice"})

    {:ok, driver} = World.join(driver, :bob, %{username: "bob"})
    game = World.state(driver)
    alice = %{game.fields.alice | yoke: yoke(%{left: 5, head: 5, right: 5}), pouring: 0.01}
    stepped = Game.step(%{game | fields: %{game.fields | alice: alice}}, @dt)

    assert stepped.fields.bob.squall.mood == :gust
    refute stepped.fields.alice.squall.mood == :gust
  end
end
