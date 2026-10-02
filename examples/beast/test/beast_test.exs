defmodule BeastTest do
  @moduledoc """
  The run: what the terrain says is solid, where the layers put the horizon, and what the
  world does to a runner who holds a key.
  """

  use ExUnit.Case, async: false

  alias Beast.{Art, Game, Scenery, Terrain}
  alias Cauldron2D.Parallax
  alias FrenchCurve.Raster

  setup_all do
    Art.install()
    :ok
  end

  describe "terrain" do
    test "the ground is solid at and under the surface and open above it" do
      assert Terrain.solid?({0, Terrain.surface()})
      assert Terrain.solid?({0, Terrain.surface() + 4})
      refute Terrain.solid?({0, Terrain.surface() - 4})
    end

    test "a ledge raises the floor and the tiles under it are stone" do
      ledges = Enum.filter(0..400, &(Terrain.floor_at(&1) < Terrain.surface()))

      assert ledges != []

      for column <- ledges do
        floor = Terrain.floor_at(column)

        assert Terrain.cell({column, floor}) == {:turf, [], nil}
        assert Terrain.cell({column, floor + 1}) == {:stone, [], nil}
      end
    end

    test "the same column always answers the same" do
      for column <- -50..50, do: assert(Terrain.floor_at(column) == Terrain.floor_at(column))
    end
  end

  describe "layers" do
    test "every layer carries a name and the backmost one fills the picture" do
      [back | rest] = Scenery.layers()

      assert back.void == :opaque
      assert Enum.all?(rest, &(&1.void == :transparent))
      assert Enum.map(Scenery.layers(), & &1.name) |> Enum.uniq() |> length() == 5
    end

    test "the layers run from still to faster than the world" do
      factors = Scenery.layers() |> Enum.map(fn layer -> elem(layer.factor, 0) end)

      assert factors == Enum.sort(factors)
      assert List.first(factors) == 0.0
      assert List.last(factors) > 1.0
    end

    test "exactly one layer is drawn in front of the world" do
      assert Enum.count(Scenery.layers(), & &1.front) == 1
    end

    test "the background composes to the pane's size and is not empty" do
      raster = Parallax.compose(Art.name(), Scenery.layers(), focus: {40.0, 11.0}, size: {44, 22})

      assert Raster.dimensions(raster) == {44 * Art.tile(), 22 * Art.tile()}
      assert colours(raster) > 8
    end

    test "moving the camera moves the near layer further than the far one" do
      still = shot(0.0)
      moved = shot(6.0)

      assert still != moved
    end
  end

  describe "the world" do
    test "a runner joins standing on the ground" do
      {:ok, state} = Game.join(Game.init([]), :one, %{})
      runner = state.runners[:one]

      assert runner.y == Terrain.floor_at(runner.x) - 1.0
      assert runner.grounded?
      assert runner.lives == 3
    end

    test "holding right carries the runner forward and faces them that way" do
      state = held(:right, 20)
      runner = state.runners[:one]

      assert runner.x > 4.0
      assert runner.facing == 1
      assert runner.running?
    end

    test "holding left faces the runner back and never walks off the start" do
      runner = held(:left, 60).runners[:one]

      assert runner.facing == -1
      assert runner.x >= 1.0
    end

    test "jumping leaves the ground and lands again" do
      airborne = held(:jump, 4).runners[:one]

      refute airborne.grounded?
      assert airborne.y < Terrain.floor_at(airborne.x) - 1.0

      released = Game.handle_input(held(:jump, 4), :one, %{held: MapSet.new(), aim: nil})
      landed = Enum.reduce(1..120, released, fn _tick, acc -> Game.step(acc, 0.02) end)

      assert landed.runners[:one].grounded?
      assert landed.runners[:one].y == Terrain.floor_at(landed.runners[:one].x) - 1.0
    end

    test "creatures are hatched ahead of the runner and left behind" do
      state = held(:right, 400)

      assert state.bats != [] or state.crawlers != []

      front = state.runners[:one].x

      for creature <- state.bats ++ state.crawlers do
        assert creature.x > front - 40
      end
    end
  end

  describe "the walk" do
    test "the legs step with the distance run, not with a clock" do
      cycle = for place <- 0..(Art.steps() - 1), do: Art.step(place * 0.55)

      assert cycle |> Enum.uniq() |> length() > 1
      assert Art.step(0.0) == Art.step(0.54)
      assert Art.step(0.0) != Art.step(0.56)
      assert Art.step(0.0) == Art.step(Art.steps() * 0.55)
    end

    test "the cycle comes back to a stride by way of a different pose" do
      [first, second | _rest] = for place <- 0..(Art.steps() - 1), do: Art.step(place * 0.55)

      assert first != second
      assert Art.step(2 * 0.55) != second
    end

    test "every art the walk steps through is in the atlas" do
      atlas = Cauldron2D.Atlas.fetch(Art.name())

      for place <- 0..(Art.steps() - 1) do
        assert Cauldron2D.Atlas.entry(atlas, Art.step(place * 0.55)) != nil
      end
    end

    test "standing still keeps the runner on one art" do
      state = held(:right, 40)
      standing = Enum.reduce(1..20, release(state), fn _tick, acc -> Game.step(acc, 0.02) end)

      refute standing.runners[:one].running?
      assert standing.runners[:one].stride == state.runners[:one].stride
    end
  end

  describe "tuning" do
    test "the numbers reach the world: a faster runner covers more ground" do
      assert travelled(run: 14.0) > travelled([]) * 1.5
    end
  end

  describe "ledges" do
    test "walking off a ledge drops the runner instead of leaving him in the air" do
      brink = Enum.find(5..400, fn x -> Terrain.floor_at(x) < Terrain.floor_at(x + 1) end)
      assert brink

      walked = standing_at(brink)
      stepped = Enum.reduce(1..12, walked, fn _tick, acc -> Game.step(acc, 0.02) end)

      assert stepped.runners[:one].x > brink + 1
      refute stepped.runners[:one].grounded?

      landed = Enum.reduce(1..120, stepped, fn _tick, acc -> Game.step(acc, 0.02) end)
      settled = landed.runners[:one]

      assert settled.grounded?
      assert settled.y == Terrain.floor_at(settled.x) - 1.0
    end

    test "a runner never hangs above the ground he is standing on" do
      state = held([:right, :jump], 1200)
      runner = state.runners[:one]

      if runner.grounded? do
        assert runner.y == Terrain.floor_at(runner.x) - 1.0
      else
        assert runner.y < Terrain.floor_at(runner.x) - 1.0
      end
    end

    test "a wall more than a step high stops the runner rather than lifting him onto it" do
      face =
        Enum.find(5..400, fn x ->
          Terrain.floor_at(x + 1) < Terrain.floor_at(x) - 1
        end)

      if face do
        walked = standing_at(face + 0.1)
        stopped = Enum.reduce(1..40, walked, fn _tick, acc -> Game.step(acc, 0.02) end)

        assert stopped.runners[:one].x < face + 1.0
      end
    end

    test "jumping carries the runner onto a ledge he cannot walk up" do
      rise = Enum.find(5..400, fn x -> Terrain.floor_at(x + 1) < Terrain.floor_at(x) end)
      assert rise

      leapt =
        rise
        |> standing_at()
        |> Game.handle_input(:one, %{held: MapSet.new([:right, :jump]), aim: nil})

      flown = Enum.reduce(1..90, leapt, fn _tick, acc -> Game.step(acc, 0.02) end)

      assert flown.runners[:one].x > rise
    end
  end

  describe "how thickly the plain is peopled" do
    test "a long run meets creatures, but not a wall of them" do
      {state, furthest} = run([:right, :jump], 1500)
      creatures = length(state.bats) + length(state.crawlers)

      assert furthest > 100
      assert creatures > 0
      assert creatures < 8
    end

    test "creatures are spaced out rather than hatched every tick" do
      state = held([:right, :jump], 600)
      ahead = Enum.map(state.bats ++ state.crawlers, & &1.x)

      assert ahead == Enum.uniq(ahead)
    end
  end

  defp release(state), do: Game.handle_input(state, :one, %{held: MapSet.new(), aim: nil})

  defp travelled(tuning) do
    {:ok, state} = Game.join(Game.init(seed: 7, tuning: tuning), :one, %{})
    state = Game.handle_input(state, :one, %{held: MapSet.new([:right]), aim: nil})
    moved = Enum.reduce(1..60, state, fn _tick, acc -> Game.step(acc, 0.02) end)

    moved.runners[:one].x - 4.0
  end

  defp run(actions, ticks) do
    {:ok, state} = Game.join(Game.init(seed: 7), :one, %{})
    held = actions |> List.wrap() |> MapSet.new()
    state = Game.handle_input(state, :one, %{held: held, aim: nil})

    Enum.reduce(1..ticks, {state, 0.0}, fn _tick, {acc, furthest} ->
      stepped = Game.step(acc, 0.02)

      {stepped, max(furthest, stepped.runners[:one].x)}
    end)
  end

  defp standing_at(x) do
    {:ok, state} = Game.join(Game.init(seed: 7), :one, %{})

    state
    |> put_in([Access.key!(:runners), :one, Access.key!(:x)], x / 1)
    |> put_in([Access.key!(:runners), :one, Access.key!(:y)], Terrain.floor_at(x) - 1.0)
    |> Game.handle_input(:one, %{held: MapSet.new([:right]), aim: nil})
  end

  defp held(actions, ticks) do
    {:ok, state} = Game.join(Game.init(seed: 7), :one, %{})
    held = actions |> List.wrap() |> MapSet.new()
    state = Game.handle_input(state, :one, %{held: held, aim: nil})

    Enum.reduce(1..ticks, state, fn _tick, acc -> Game.step(acc, 0.02) end)
  end

  defp shot(x) do
    Art.name()
    |> Parallax.compose(Scenery.layers(), focus: {x, 11.0}, size: {44, 22})
    |> Raster.to_rgba_binary()
  end

  defp colours(raster) do
    raster
    |> Raster.to_rgba_binary()
    |> then(&for(<<pixel::binary-size(4) <- &1>>, do: pixel))
    |> Enum.uniq()
    |> length()
  end
end
