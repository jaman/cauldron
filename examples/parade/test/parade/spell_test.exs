defmodule Parade.SpellTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Projection.Volume
  alias Parade.{Game, Spell}

  defp held(actions), do: %{held: MapSet.new(actions), aim: nil}

  defp playing do
    game = Game.init(seed: 1)
    {:ok, game} = Game.join(game, :me, %{username: "tester"})
    game
  end

  defp aiming(game), do: Game.view(game, :me).volumes

  defp facing_east(game) do
    game
    |> Game.handle_input(:me, held([:right]))
    |> Game.step(0.05)
    |> Game.handle_input(:me, held([]))
  end

  describe "aiming and casting" do
    test "holding a key shows the area and casts nothing" do
      game = playing() |> Game.handle_input(:me, held([:gale]))

      assert [%{shape: {:cone, _length, _spread, _heading, _tall}}] = aiming(game)
      assert game.spells == []
    end

    test "letting go casts it and the area stays up on its own" do
      game =
        playing()
        |> Game.handle_input(:me, held([:bless]))
        |> Game.handle_input(:me, held([]))

      assert [%{kind: :bless}] = game.spells
      assert [%{shape: {:sphere, _radius, _height}}] = aiming(game)
    end

    test "a cast area is stronger than the one being aimed" do
      aimed = playing() |> Game.handle_input(:me, held([:bless])) |> aiming() |> hd()

      cast =
        playing()
        |> Game.handle_input(:me, held([:bless]))
        |> Game.handle_input(:me, held([]))
        |> Game.step(0.3)
        |> aiming()
        |> hd()

      assert cast.strength > aimed.strength
    end

    test "a spell drops off once its time is up" do
      game =
        playing()
        |> Game.handle_input(:me, held([:gale]))
        |> Game.handle_input(:me, held([]))
        |> Game.step(30.0)

      assert game.spells == []
      assert aiming(game) == []
    end

    test "holding squares marks the area out in whole tiles" do
      game = playing() |> Game.handle_input(:me, held([:bless, :squares]))

      assert [%{shape: {:cells, tiles, _tall}, falloff: :flat}] = aiming(game)
      assert MapSet.size(tiles) > 1
    end
  end

  describe "the shapes a spell takes" do
    test "a cone follows the way the knight faces, not where the camera looks" do
      game =
        playing()
        |> facing_east()
        |> Game.handle_input(:me, Map.put(held([:gale]), :heading, 1.25))

      assert [%{shape: {:cone, _length, _spread, heading, _tall}}] = aiming(game)
      assert_in_delta heading, 0.0, 1.0e-6
    end

    test "a burst lands ahead of the caster, not on them" do
      game = playing() |> facing_east() |> Game.handle_input(:me, held([:acid]))
      [%{at: {x, _y}}] = aiming(game)
      %{mover: %{x: from}} = game.players[:me]

      assert x > from + 1.0
    end

    test "every spell gives a volume the engine accepts" do
      for kind <- Spell.kinds() do
        volume = Spell.aimed(kind, {4.0, 4.0}, 0.3, :measured)

        assert %{shape: {_module, _data}} = Volume.new(volume)
      end
    end
  end

  describe "what a cast area keeps up with" do
    defp cast(game, kind) do
      game
      |> Game.handle_input(:me, held([kind]))
      |> Game.handle_input(:me, held([]))
    end

    defp area(game), do: game |> aiming() |> hd()

    test "an emanation from the caster's own space goes where they go" do
      game = playing() |> cast(:bless)
      was = area(game).at

      walked =
        game
        |> Game.handle_input(:me, held([:right]))
        |> Game.step(0.4)

      assert elem(area(walked).at, 0) > elem(was, 0) + 0.2
    end

    test "an emanation laid on somebody else stays on them as they wander" do
      game = playing() |> cast(:bane)

      standing_on = fn held ->
        Enum.find_index(held.walkers, &({&1.mover.x, &1.mover.y} == area(held).at))
      end

      knight = standing_on.(game)

      assert knight != nil

      wandered = Enum.reduce(1..120, game, fn _, acc -> Game.step(acc, 0.05) end)

      assert standing_on.(wandered) == knight
      assert area(wandered).at != area(game).at
    end

    test "a cone stays where it was cast, however far the caster walks" do
      game = playing() |> cast(:gale)
      was = area(game).at

      walked =
        game
        |> Game.handle_input(:me, held([:right]))
        |> Game.step(0.4)

      assert area(walked).at == was
    end

    test "an area whose subject leaves goes with them" do
      game = playing() |> cast(:bless)

      assert [_bless] = aiming(game)
      assert Game.view(Game.leave(game, :me), :me).volumes == []
    end
  end

  describe "walking to a click" do
    test "letting go of the pointer over a tile sets a way there" do
      game =
        playing()
        |> Game.handle_input(:me, Map.put(held([:go]), :aim, {6.5, 6.5}))
        |> Game.handle_input(:me, Map.put(held([]), :aim, {6.5, 6.5}))

      assert game.players[:me].route != []
    end

    test "the knight walks it and stops when it arrives" do
      game =
        playing()
        |> Game.handle_input(:me, Map.put(held([:go]), :aim, {6.5, 6.5}))
        |> Game.handle_input(:me, Map.put(held([]), :aim, {6.5, 6.5}))
        |> then(fn game -> Enum.reduce(1..400, game, fn _, acc -> Game.step(acc, 0.05) end) end)

      %{mover: mover, route: route} = game.players[:me]

      assert route == []
      assert_in_delta mover.x, 6.5, 0.6
      assert_in_delta mover.y, 6.5, 0.6
    end

    test "a direction key takes the way away" do
      game =
        playing()
        |> Game.handle_input(:me, Map.put(held([:go]), :aim, {6.5, 6.5}))
        |> Game.handle_input(:me, Map.put(held([]), :aim, {6.5, 6.5}))

      assert game.players[:me].route != []

      pressed = game |> Game.handle_input(:me, held([:up])) |> Game.step(0.05)

      assert pressed.players[:me].route == []
    end

    test "a click with no aim, or nowhere to go, leaves the knight alone" do
      game =
        playing()
        |> Game.handle_input(:me, held([:go]))
        |> Game.handle_input(:me, held([]))

      assert game.players[:me].route == []
    end
  end
end
