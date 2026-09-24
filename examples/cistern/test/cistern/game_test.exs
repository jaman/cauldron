defmodule Cistern.GameTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Test, as: World
  alias Cistern.Game

  defp driver(opts \\ []) do
    {:ok, driver} =
      Game
      |> World.new(game_opts: Keyword.merge([seed: 1], opts), hz: 30)
      |> World.join(:alice, %{username: "alice"})

    driver
  end

  test "a held key moves the bucket, and the pointer takes it where it points" do
    start = World.view(driver(), :alice).me.x
    walked = driver() |> World.hold(:alice, [:right]) |> World.tick(15)
    assert World.view(walked, :alice).me.x > start

    at = 4.5
    pointed = driver() |> World.hold(:alice, [], {at, 5.0}) |> World.tick(60)
    middle = World.view(pointed, :alice).me.x + Game.bucket_wide() / 2

    assert_in_delta middle, at, 0.01
  end

  test "drops fall, and one that lands on a bucket is caught" do
    {:ok, driver} =
      World.until(
        driver(tuning: [spawn_every: 0.3, fall: 6.0]),
        &(World.view(&1, :alice).drops != []),
        60
      )

    drop = hd(World.view(driver, :alice).drops)

    {:ok, landed} =
      driver
      |> World.hold(:alice, [], {drop.x + 0.5, 0.0})
      |> World.until(
        &Enum.any?(World.events(&1), fn event -> match?({:catch, _, _}, event) end),
        120
      )

    assert World.view(landed, :alice).me.score >= 1
  end

  test "three misses and the player is out, with a summary" do
    {:ok, driver} =
      World.until(
        driver(tuning: [spawn_every: 0.2, fall: 12.0]),
        &(World.view(&1, :alice).me.misses >= 3),
        900
      )

    view = World.view(driver, :alice)
    assert {:out, :alice} in World.events(driver)
    assert %{title: "The cistern overflows", next: :same_world} = Game.outcome(view)
  end

  test "the same seed replays the same rain" do
    a = driver() |> World.tick(300) |> World.view(:alice)
    b = driver() |> World.tick(300) |> World.view(:alice)
    assert a.drops == b.drops
  end
end
