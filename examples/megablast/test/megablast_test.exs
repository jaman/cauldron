defmodule MegablastTest do
  @moduledoc """
  The lane: where the rock leaves room, what a wave does when it enters, and what the ship
  does with a held key.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.{Parallax, Rng}
  alias FrenchCurve.Raster
  alias Megablast.{Art, Game, Lane, Music, Scenery, Wave}

  setup_all do
    Art.install()
    {:ok, lane: Lane.new(), shapes: Wave.new()}
  end

  describe "the lane" do
    setup %{lane: lane}, do: {:ok, lane: lane}

    test "rock stands outside the open span and nothing inside it", %{lane: lane} do
      for y <- -60..60 do
        {left, right} = Lane.edges(lane, y)

        assert Lane.cell(lane, {left - 1, y}) != :void
        assert Lane.cell(lane, {right + 1, y}) != :void
        assert Lane.cell(lane, {left, y}) == :void
        assert Lane.cell(lane, {right, y}) == :void
      end
    end

    test "the walls are on the sides and never meet in the middle", %{lane: lane} do
      middle = Lane.middle(lane)

      for y <- -200..200 do
        {left, right} = Lane.edges(lane, y)

        assert left < middle
        assert right > middle
        assert right - left >= 8
      end
    end

    test "the walls change thickness down the lane rather than staying square", %{lane: lane} do
      widths = for y <- -200..200, do: Lane.edges(lane, y) |> then(fn {l, r} -> r - l end)

      assert widths |> Enum.uniq() |> length() > 3
    end

    test "the same row always answers the same", %{lane: lane} do
      for y <- -40..40, do: assert(Lane.edges(lane, y) == Lane.edges(lane, y))
    end

    test "open? agrees with the edges", %{lane: lane} do
      for y <- -30..30 do
        {left, right} = Lane.edges(lane, y)

        assert Lane.open?(lane, left + 0.5, y)
        refute Lane.open?(lane, left - 0.5, y)
        refute Lane.open?(lane, right + 1.5, y)
      end
    end

    test "turrets grow out of a wall, spaced down the lane, the same ones every time", %{
      lane: lane
    } do
      steps = -40..0
      turrets = for step <- steps, turret = Lane.turret_of(lane, step), do: turret

      assert length(turrets) > 10
      assert length(turrets) < Enum.count(steps)

      for turret <- turrets do
        {left, right} = Lane.edges(lane, turret.y)

        assert turret.x == left - 1 or turret.x == right + 1
        assert Lane.turret_of(lane, Lane.turret_step(lane, turret.y)) == turret
      end
    end
  end

  describe "waves" do
    test "a wave is several creatures of one kind, inside the lane", %{lane: lane, shapes: shapes} do
      {creatures, _rng} = Wave.next(shapes, 0, -30.0, Rng.new(5), lane)

      assert length(creatures) > 2
      assert creatures |> Enum.map(& &1.kind) |> Enum.uniq() |> length() == 1

      for creature <- creatures, do: assert(Lane.open?(lane, creature.x, creature.y))
    end

    test "the waves differ from one another rather than repeating one shape", %{
      lane: lane,
      shapes: shapes
    } do
      kinds =
        for number <- 0..(Wave.count() - 1) do
          {creatures, _rng} = Wave.next(shapes, number, -30.0, Rng.new(7), lane)
          {hd(creatures).kind, length(creatures), hd(creatures).path}
        end

      assert kinds |> Enum.uniq() |> length() > 2
    end

    test "flying carries a creature down the lane", %{lane: lane, shapes: shapes} do
      {[creature | _rest], _rng} = Wave.next(shapes, 0, -30.0, Rng.new(9), lane)
      moved = Enum.reduce(1..50, creature, fn _tick, acc -> Wave.fly(acc, 0.02) end)

      assert moved.y > creature.y
    end

    test "a sweeping creature swings across the lane and comes back", %{
      lane: lane,
      shapes: shapes
    } do
      {[creature | _rest], _rng} = Wave.next(shapes, 0, -30.0, Rng.new(11), lane)

      across =
        Enum.map_reduce(1..300, creature, fn _tick, acc ->
          flown = Wave.fly(acc, 0.02)
          {flown.x, flown}
        end)
        |> elem(0)

      assert Enum.max(across) - Enum.min(across) > 3.0
    end
  end

  describe "tuning" do
    test "the numbers reach the world: a faster lane carries the view further" do
      assert depth_after(scroll: 12.0) < depth_after([]) * 1.5
    end
  end

  describe "the ship" do
    test "a pilot starts between the walls with shields and no drones", %{lane: lane} do
      {:ok, state} = Game.join(Game.init([]), :one, %{})
      pilot = state.pilots[:one]
      {left, right} = Lane.edges(lane, pilot.y)

      assert pilot.x > left and pilot.x < right
      assert pilot.shields == 3
      assert pilot.addons == 0
    end

    test "steering banks the ship and the rock stops it", %{lane: lane} do
      pilot = held([:right], 200).pilots[:one]
      {_left, right} = Lane.edges(lane, pilot.y)

      assert pilot.bank == 2
      assert pilot.x <= right
    end

    test "braking shows the retro flame" do
      assert held([:brake], 10).pilots[:one].braking?
      refute held([:thrust], 10).pilots[:one].braking?
    end

    test "flying to the bottom holds the view back rather than leaving the ship behind" do
      state = held([:brake], 250)
      pilot = state.pilots[:one]

      assert pilot.y - state.depth < 12.0
      assert state.depth > -40.0
    end

    test "letting the lane carry you keeps the view moving on" do
      assert held([], 250).depth < -20.0
    end

    test "firing sends shots up the lane, and drones fire with the ship" do
      bare = held([:fire], 30)
      {:ok, armed} = Game.join(Game.init(seed: 3), :two, %{})
      armed = put_in(armed.pilots[:two].addons, 2)

      armed =
        armed
        |> Game.handle_input(:two, %{held: MapSet.new([:fire]), aim: nil})
        |> Game.step(0.02)

      assert length(bare.shots) > 0
      assert length(armed.shots) == 5
    end

    test "a shot that reaches a drone removes it and scores" do
      {:ok, state} = Game.join(Game.init(seed: 3), :one, %{})
      pilot = state.pilots[:one]

      drone = creature(:drone, pilot.x, pilot.y - 4.0)

      after_tick =
        %{state | foes: [drone], shots: [%{x: pilot.x, y: pilot.y - 4.0}], waved_to: -1000.0}
        |> Game.step(0.02)

      refute Enum.any?(after_tick.foes, &(&1.kind == :drone))
      assert after_tick.shots == []
      assert after_tick.pilots[:one].score > 0
    end

    test "a pod adds a drone to the ship and a hit takes them away" do
      assert meeting(:pod).addons == 1
      assert meeting(:pod).score > 0
      assert meeting(:drone).shields == 2
      assert meeting(:drone).addons == 0
    end
  end

  describe "how thickly the lane is peopled" do
    test "a long run meets waves, not a glut" do
      state = held([], 1500)

      assert state.waves > 3
      assert length(state.foes) < 14
    end
  end

  describe "layers" do
    test "the backmost layer fills the picture and the rest let it through" do
      [back | rest] = Scenery.layers()

      assert back.void == :opaque
      assert Enum.all?(rest, &(&1.void == :transparent))
    end

    test "the layers run from nearly still to faster than the lane" do
      factors = Scenery.layers() |> Enum.map(fn layer -> elem(layer.factor, 1) end)

      assert factors == Enum.sort(factors)
      assert List.first(factors) < 0.2
      assert List.last(factors) > 1.0
    end

    test "the background composes to the pane's size and is not empty" do
      raster = Parallax.compose(Art.name(), Scenery.layers(), focus: {12.0, 0.0}, size: {26, 17})

      assert Raster.dimensions(raster) == {26 * Art.tile(), 17 * Art.tile()}
      assert colours(raster) > 8
    end
  end

  describe "music" do
    test "the piece is one loop at the lane's tempo, or nothing when the file is missing" do
      case Music.piece() do
        nil ->
          assert Music.cue() == nil

        {name, spec} ->
          assert name == Music.name()
          assert spec.layers == [:track]
          assert Map.has_key?(spec.sections, :run)
          assert Music.cue().piece == name
      end
    end
  end

  defp held(actions, ticks) do
    {:ok, state} = Game.join(Game.init(seed: 11), :one, %{})
    state = Game.handle_input(state, :one, %{held: MapSet.new(actions), aim: nil})

    Enum.reduce(1..ticks, state, fn _tick, acc -> Game.step(acc, 0.02) end)
  end

  defp depth_after(tuning) do
    {:ok, state} = Game.join(Game.init(seed: 11, tuning: tuning), :one, %{})

    Enum.reduce(1..100, state, fn _tick, acc -> Game.step(acc, 0.02) end).depth
  end

  defp creature(kind, x, y) do
    %{
      kind: kind,
      x: x,
      y: y,
      path: :drift,
      lane: x,
      phase: 0.0,
      age: 0.0,
      fall: 2.4,
      reach: 0.0,
      rate: 0.0
    }
  end

  defp meeting(kind) do
    {:ok, state} = Game.join(Game.init(seed: 5), :one, %{})
    pilot = state.pilots[:one]

    foe = %{
      kind: kind,
      x: pilot.x,
      y: pilot.y,
      path: :drift,
      lane: pilot.x,
      phase: 0.0,
      age: 0.0,
      fall: 2.4,
      reach: 0.0,
      rate: 0.0
    }

    %{state | foes: [foe], waved_to: -1000.0}
    |> Game.step(0.02)
    |> get_in([Access.key!(:pilots), :one])
  end

  defp colours(raster) do
    raster
    |> Raster.to_rgba_binary()
    |> then(&for(<<pixel::binary-size(4) <- &1>>, do: pixel))
    |> Enum.uniq()
    |> length()
  end
end
