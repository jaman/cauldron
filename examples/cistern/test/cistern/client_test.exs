defmodule Cistern.ClientTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Atlas, Test}
  alias Cauldron2D.Client.Hud
  alias Cistern.{Art, Client, Game, Sound}

  test "the atlas loads from the pic files, the gold drop derived from the drop" do
    assert Art.install() == :cistern
    atlas = Atlas.fetch(:cistern)
    assert Enum.sort(Atlas.arts(atlas)) == [:bucket, :drop, :drop_gold, :floor, :sky]
    assert length(Atlas.entry(atlas, :drop).frames) == 2
    assert Atlas.entry(atlas, :drop_gold).fps == 6
  end

  test "the scene, the hud, the cue and the sounds come from the view" do
    {:ok, driver} =
      Game |> Test.new(game_opts: [seed: 1], hz: 30) |> Test.join(:alice, %{username: "alice"})

    view = Test.view(driver, :alice)

    scene = Client.scene(view)
    assert scene.bounds == {12, 10}
    assert scene.cell.({0, 9}) == {:floor, [], nil}
    assert scene.cell.({0, 0}) == {:sky, [], nil}
    assert Enum.count(scene.movers, &(elem(&1, 0) == :bucket)) == 2
    assert [{"alice", _at, _colour}] = scene.labels

    assert Hud.rows(Client.hud(view))
           |> Enum.map(&Hud.text/1)
           |> Enum.any?(&(&1 =~ "caught 0"))

    assert Client.cue(view, :arena).section == :calm
    assert Client.cue(view, :title) == nil
    assert Sound.voice({:catch, :drop_gold}) != nil
    assert Client.outcome(view) == nil
  end

  test "the arenas register, and the robot walks under the lowest drop" do
    :ok = Cistern.Arenas.register()
    assert Enum.map(Cauldron2D.Arenas.list(), & &1.id) |> Enum.sort() == [:contest, :yard]

    view = %{
      me: %{x: 5.0, misses: 0},
      drops: [%{x: 1, y: 2.0}, %{x: 9, y: 7.0}],
      misses_allowed: 3
    }

    assert {%{held: held}, nil} = Cistern.Brain.decide(view, nil, %{tick: 1, skill: 1.0})
    assert MapSet.member?(held, :right)
    refute Cistern.Brain.gone?(view)
    assert Cistern.Brain.gone?(%{view | me: nil})
  end
end
