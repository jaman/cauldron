defmodule Cistern.GameTest do
  use ExUnit.Case, async: true

  alias Cauldron.Test, as: World
  alias Cistern.{Field, Game, Storm, Tuning}

  @tuning Tuning.new()
  @dt 1 / 30

  defp field(changes) do
    :alice |> Field.new("alice", 1) |> Map.put(:until_drop, 5.0) |> Map.merge(Map.new(changes))
  end

  test "a drop into the head jar's mouth is caught for the storm's worth" do
    {caught, events} = Field.step(field(drops: [%{x: 8.0, y: 7.8}], level: 3), @dt, @tuning)

    assert caught.drops == []
    assert caught.score == 3
    assert caught.caught == 1
    assert [{:catch, _at}] = Enum.filter(events, &match?({:catch, _}, &1))
  end

  test "a miss breaks the jar on its side, splashes the rain and sets the storm back" do
    drops = [%{x: 4.0, y: 10.19}, %{x: 12.0, y: 5.0}]
    {missed, events} = Field.step(field(drops: drops, level: 3, released: 7), @dt, @tuning)

    assert missed.sides == MapSet.new([:right])
    assert missed.drops == []
    assert length(missed.splashes) == 2
    assert missed.level == 2
    assert missed.released == 0
    assert missed.lull > 0
    assert missed.squall.mood == :grin
    assert Enum.any?(events, &match?({:miss, _}, &1))
  end

  test "with no side jars left, a miss breaks the head jar and the keeper is out" do
    {out, events} =
      Field.step(field(drops: [%{x: 3.0, y: 10.19}], sides: MapSet.new()), @dt, @tuning)

    assert out.out?
    assert Field.jar_count(out) == 0
    assert {:out, :alice} in events
  end

  test "a streak of catches mends a broken side jar" do
    needed = Cauldron.Tuning.get(@tuning, :streak)
    start = field(drops: [%{x: 8.0, y: 7.8}], sides: MapSet.new([:right]), streak: needed - 1)
    {mended, events} = Field.step(start, @dt, @tuning)

    assert mended.sides == MapSet.new([:left, :right])
    assert mended.streak == 0
    assert Enum.any?(events, &match?({:mend, _}, &1))
  end

  test "a storm whose drops have all come down gives way to the next" do
    drops = Storm.pace(@tuning, 1).drops
    {next, events} = Field.step(field(released: drops, drops: []), @dt, @tuning)

    assert next.level == 2
    assert next.released == 0
    assert Enum.any?(events, &match?({{:storm, 2}, _}, &1))
    assert Storm.pace(@tuning, 2).drop_every < Storm.pace(@tuning, 1).drop_every
  end

  test "every keeper has a square of their own, rained on from the same seed" do
    {:ok, driver} =
      Game
      |> World.new(game_opts: [seed: 7], hz: 30)
      |> World.join(:alice, %{username: "alice"})

    {:ok, driver} = World.join(driver, :bob, %{username: "bob"})
    driver = World.tick(driver, 120)

    alice = World.view(driver, :alice)
    bob = World.view(driver, :bob)
    assert alice.me.drops == bob.me.drops
    assert alice.me.offset != bob.me.offset
    assert [%{name: "bob"}] = alice.rivals
  end
end
