defmodule Cauldron2D.Replay.ViewerTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Player, Replay, World}
  alias Cauldron2D.TestGames.Race

  test "a replay is played back to a watcher as frames for one recorded player, then done" do
    {:ok, world} = World.start_link(game: Race, hz: 100, record: true, game_opts: [seed: 4])
    :ok = Player.join(world, :alice, %{speed: 3.0})
    Player.input(world, :alice, %{held: MapSet.new([:forward]), aim: nil})
    Process.sleep(120)
    :ok = World.pause(world)
    replay = World.replay(world)
    final = World.snapshot(world)
    GenServer.stop(world)

    {:ok, viewer} =
      Replay.Viewer.start_link(
        replay: replay,
        game: Race,
        game_opts: [seed: 4],
        hz: 100,
        speed: 10,
        as: :alice,
        watcher: self()
      )

    assert_receive {:cauldron_frame, %{tick: 1, view: %{me: _}}}, 500
    assert_receive {:cauldron_replay, ^viewer, :done, state}, 2_000
    assert state.players.alice.x == final.players.alice.x
    assert state.ticks == final.ticks
  end

  test "a viewer can be paused and stepped" do
    replay = Replay.new() |> Replay.record(0, {:join, :alice, %{}}) |> Replay.stepped(5)

    {:ok, viewer} =
      Replay.Viewer.start_link(
        replay: replay,
        game: Race,
        hz: 100,
        speed: 10,
        as: :alice,
        watcher: self(),
        paused?: true
      )

    refute_receive {:cauldron_frame, _}, 50
    :ok = Replay.Viewer.step(viewer)
    assert_receive {:cauldron_frame, %{tick: 1}}, 200
    refute_receive {:cauldron_frame, _}, 50
    :ok = Replay.Viewer.resume(viewer)
    assert_receive {:cauldron_replay, ^viewer, :done, _}, 500
  end
end
