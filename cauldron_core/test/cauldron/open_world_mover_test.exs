defmodule Cauldron.OpenWorldMoverTest do
  use ExUnit.Case, async: true

  alias Cauldron.OpenWorld.{Cell, Mover}
  alias Cauldron.OpenWorld.Map, as: World

  @pace %{
    run: 4.0,
    dash: 7.0,
    climb: 1.5,
    swim: 2.0,
    quicken: 40.0,
    turn: 20.0,
    leap: 6.0,
    fall: 20.0,
    steep: 1.0,
    ledge: 0.5,
    float: 1.0,
    draft: 0.8,
    radius: 0.3,
    tire_dash: 0.1,
    tire_climb: 0.2,
    tire_swim: 0.0,
    rest: 0.5
  }

  defp land(height, opts \\ []) do
    World.new(cell_size: 64.0, samples: 64)
    |> World.put(Cell.sampled({0, 0}, 64, 64.0, height, opts))
  end

  defp run(mover, map, intent, steps) do
    Enum.reduce(1..steps, mover, fn _step, mover -> Mover.step(mover, map, intent, @pace, 1 / 60) end)
  end

  defp east, do: %{toward: {1.0, 0.0}, dash: false, leap: false}

  test "on level ground it reaches its run speed and keeps to the ground" do
    map = land(fn _point -> 2.0 end)
    mover = map |> then(&Mover.new({10.0, 10.0}, &1)) |> run(map, east(), 120)

    assert mover.mode == :ground
    assert mover.speed == 4.0
    assert mover.height == 2.0
    assert_in_delta elem(mover.point, 0), 10.0 + 4.0 * 2.0, 0.3
  end

  test "it climbs ground that rises faster than it can walk, spending stamina" do
    map = land(fn {x, _y} -> max(0.0, 3.0 * (x - 20.0)) end)
    mover = map |> then(&Mover.new({15.0, 10.0}, &1)) |> run(map, east(), 240)

    assert mover.mode == :climb
    assert mover.height > 1.0
    assert mover.stamina < 1.0
  end

  test "it swims where the water is deeper than it floats in" do
    map = land(fn {x, _y} -> -0.2 * (x - 10.0) end, water: 0.0)
    mover = map |> then(&Mover.new({10.0, 10.0}, &1)) |> run(map, east(), 300)

    assert mover.mode == :swim
    assert mover.height == -0.8
  end

  test "a leap leaves the ground and comes back down to it" do
    map = land(fn _point -> 0.0 end)
    still = %{toward: {0.0, 0.0}, dash: false, leap: false}
    risen = Mover.step(Mover.new({10.0, 10.0}, map), map, %{still | leap: true}, @pace, 1 / 60)
    landed = run(risen, map, still, 60)

    assert risen.mode == :air
    assert landed.mode == :ground
    assert landed.height == 0.0
  end
end
