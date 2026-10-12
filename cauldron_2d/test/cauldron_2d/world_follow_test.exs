defmodule Cauldron2D.WorldFollowTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.TestGames.Race
  alias Cauldron2D.World

  test "a follower runs the host's joins, input and steps and ends at the host's state" do
    {:ok, host} = World.start_link(game: Race, hz: 100)
    {:ok, follower} = World.start_link(game: Race, follow: host)

    :ok = World.join(host, :on_host, %{})
    :ok = World.join(follower, :on_follower, %{speed: 2.0})
    assert World.join(follower, :third, %{}) == {:error, :full}

    World.input(host, :on_host, %{held: MapSet.new([:forward]), aim: nil})
    World.input(follower, :on_follower, %{held: MapSet.new([:forward]), aim: nil})
    Process.sleep(300)
    :ok = World.pause(host)
    Process.sleep(100)

    host_state = World.snapshot(host)
    assert host_state.players.on_follower.x > 0.0
    assert World.snapshot(follower) == host_state
  end

  test "a follower stops when its host does" do
    {:ok, host} = World.start(game: Race, hz: 100)
    {:ok, follower} = World.start(game: Race, follow: host)
    watch = Process.monitor(follower)

    GenServer.stop(host)

    assert_receive {:DOWN, ^watch, :process, ^follower, :normal}, 1_000
  end
end
