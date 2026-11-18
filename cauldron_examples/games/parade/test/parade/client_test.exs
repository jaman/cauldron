defmodule Parade.ClientTest do
  use ExUnit.Case, async: false

  alias Parade.{Client, Game, Spell}

  defp held(actions), do: %{held: MapSet.new(actions), aim: nil}

  defp playing do
    game = Game.init(seed: 3)
    {:ok, game} = Game.join(game, :me, %{username: "tester"})
    game
  end

  defp scene(game), do: Client.scene(Game.view(game, :me))

  describe "scene/1 reads every key the view promises" do
    test "with nothing happening" do
      built = scene(playing())

      assert {_x, _y} = built.focus
      assert built.volumes == []
      assert built.labels == []
      assert is_list(built.movers)
    end

    test "while a spell is being aimed" do
      built = playing() |> Game.handle_input(:me, held([:gale])) |> scene()

      assert [%{shape: {:cone, _, _, _, _}}] = built.volumes
    end

    test "while a spell is up and following its subject" do
      built =
        playing()
        |> Game.handle_input(:me, held([:bless]))
        |> Game.handle_input(:me, held([]))
        |> Game.step(0.2)
        |> scene()

      assert [%{shape: {:sphere, _, _}}] = built.volumes
    end

    test "while walking a route, which it draws" do
      built =
        playing()
        |> Game.handle_input(:me, Map.put(held([:go]), :aim, {6.5, 6.5}))
        |> Game.handle_input(:me, Map.put(held([]), :aim, {6.5, 6.5}))
        |> scene()

      assert length(built.labels) > 1
      assert {"×", _goal, _colour} = List.last(built.labels)
    end

    test "with an area marked out in squares" do
      built =
        playing()
        |> Game.handle_input(:me, held([:bless, :squares]))
        |> scene()

      assert [%{shape: {:cells, _tiles, _tall}}] = built.volumes
    end
  end

  describe "hud/1 reads every key the view promises" do
    test "for a player and for a watcher" do
      assert [_ | _] = Client.hud(Game.view(playing(), :me))
      assert [["watching"]] = Client.hud(%{me: nil})
    end
  end

  describe "the client and the game agree on the actions" do
    test "every spell is an action, and is bound to a key" do
      bound = Client.keymaps() |> Keyword.fetch!(:arrows) |> Map.keys()

      for kind <- Spell.kinds() do
        assert kind in Client.actions()
        assert kind in bound
      end

      assert :go in Client.actions()
      assert :go in bound
    end
  end
end
