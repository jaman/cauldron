defmodule Town.GameTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Test, as: Driver
  alias Town.Game

  setup do
    driver = Driver.new(Game, game_opts: [seed: 7, villagers: 3], hz: 30)
    {:ok, driver} = Driver.join(driver, "alice", %{username: "alice"})
    {:ok, driver: driver}
  end

  defp me(driver), do: Driver.view(driver, "alice").me

  test "the view carries the player's mover beside the villagers'", %{driver: driver} do
    assert length(Driver.view(driver, "alice").movers) == 4
  end

  test "holding a direction walks, and stops at a wall", %{driver: driver} do
    walked = driver |> Driver.hold("alice", [:up]) |> Driver.tick(15)
    assert me(walked).mover.y < 21.5
    assert Game.walking?(me(walked).mover, Driver.view(walked, "alice").elapsed)

    rested = walked |> Driver.hold("alice", []) |> Driver.tick(10)
    refute Game.walking?(me(rested).mover, Driver.view(rested, "alice").elapsed)

    blocked = driver |> Driver.hold("alice", [:left]) |> Driver.tick(300)
    assert me(blocked).mover.x > 0.5
  end

  test "picking yourself selects, pointing shows the way and its distance, picking again walks it",
       %{driver: driver} do
    selected =
      driver
      |> Driver.hold("alice", [:pick], {22.5, 21.5})
      |> Driver.tick()
      |> Driver.hold("alice", [], {22.5, 21.5})
      |> Driver.tick()

    assert me(selected).selected?

    aimed = selected |> Driver.hold("alice", [], {22.5, 17.5}) |> Driver.tick()
    assert {path, distance} = me(aimed).way
    assert length(path) == 4
    assert_in_delta distance, 4.0, 0.001

    sent =
      aimed
      |> Driver.hold("alice", [:pick], {22.5, 17.5})
      |> Driver.tick()
      |> Driver.hold("alice", [], nil)
      |> Driver.tick(90)

    refute me(sent).selected?
    assert_in_delta me(sent).mover.y, 17.5, 0.01
  end

  test "cancel puts a selection down and the ruler and range keys change the rules",
       %{driver: driver} do
    selected =
      driver
      |> Driver.hold("alice", [:pick], {22.5, 21.5})
      |> Driver.tick()
      |> Driver.hold("alice", [], nil)
      |> Driver.tick()

    assert me(selected).selected?

    cancelled = selected |> Driver.hold("alice", [:cancel]) |> Driver.tick()
    refute me(cancelled).selected?

    ruled =
      cancelled
      |> Driver.hold("alice", [:ruler])
      |> Driver.tick()
      |> Driver.hold("alice", [])
      |> Driver.tick()

    assert Driver.view(ruled, "alice").ruler == :dnd

    ranged = ruled |> Driver.hold("alice", [:range]) |> Driver.tick()
    assert Driver.view(ranged, "alice").range == 6
  end

  test "a way beyond the range is refused", %{driver: driver} do
    ranged =
      driver
      |> Driver.hold("alice", [:range, :pick], {22.5, 21.5})
      |> Driver.tick()
      |> Driver.hold("alice", [], {22.5, 5.5})
      |> Driver.tick()

    assert me(ranged).selected?
    assert me(ranged).way == nil
  end

  test "villagers wander along the paving", %{driver: driver} do
    before = driver |> Driver.view("alice") |> Map.fetch!(:movers) |> Enum.take(3)

    later =
      driver |> Driver.tick(150) |> Driver.view("alice") |> Map.fetch!(:movers) |> Enum.take(3)

    assert Enum.any?(Enum.zip(before, later), fn {a, b} -> {a.x, a.y} != {b.x, b.y} end)
    assert Enum.all?(later, &Town.Legend.walkable?({&1.x, &1.y}))
  end
end
