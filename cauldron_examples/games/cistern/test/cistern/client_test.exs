defmodule Cistern.ClientTest do
  use ExUnit.Case, async: false

  alias Cauldron.Client.Hud
  alias Cauldron.Test
  alias Cistern.{Client, Game, Sound}

  test "the scene, the hud, the cue and the sounds come from the view" do
    {:ok, driver} =
      Game |> Test.new(game_opts: [seed: 1], hz: 30) |> Test.join(:alice, %{username: "alice"})

    view = Test.view(driver, :alice)
    scene = Client.scene(view)

    assert scene.bounds == {16, 12}
    assert scene.cell.({0, 11}) == {:ground, [], nil}
    assert Enum.count(scene.movers, &(elem(&1, 0) in [:jar, :jar_head])) == 3
    assert Enum.any?(scene.movers, &(elem(&1, 0) == :squall))

    assert Hud.rows(Client.hud(view))
           |> Enum.map(&Hud.text/1)
           |> Enum.any?(&(&1 =~ "STORM 1"))

    assert Client.cue(view, :play).section == :calm
    assert Client.cue(view, :title) == nil
    assert Sound.voice(:catch) != nil
    assert Client.outcome(view) == nil
  end

  test "the worlds register, and the robot walks under the lowest drop" do
    :ok = Cistern.Worlds.register()
    assert Enum.map(Cauldron.Worlds.list(), & &1.id) |> Enum.sort() == [:contest, :yard]

    me = %{
      centre: 5.0,
      out?: false,
      squall: %{x: 2.0},
      drops: [%{x: 1.0, y: 2.0}, %{x: 9.0, y: 7.0}]
    }

    assert {%{held: held}, nil} = Cistern.Brain.decide(%{me: me}, nil, %{tick: 1, skill: 1.0})
    assert MapSet.member?(held, :right)
    refute Cistern.Brain.gone?(%{me: me})
    assert Cistern.Brain.gone?(%{me: nil})
  end
end
