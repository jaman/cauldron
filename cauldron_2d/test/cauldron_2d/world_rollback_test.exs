defmodule Cauldron2D.WorldRollbackTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.TestGames.Race
  alias Cauldron2D.World

  test "two worlds playing with rollback, input always arriving late, end at the same state with both players' input" do
    {:ok, host} = World.start_link(game: Race, hz: 100)
    {:ok, other} = World.start_link(game: Race, follow: host, rollback: [delay: 0])

    :ok = World.join(host, :on_host, %{})
    :ok = World.join(other, :on_other, %{speed: 2.0})
    Process.sleep(100)

    World.input(host, :on_host, %{held: MapSet.new([:forward]), aim: nil})
    World.input(other, :on_other, %{held: MapSet.new([:forward]), aim: nil})
    Process.sleep(200)
    World.input(other, :on_other, %{held: MapSet.new(), aim: nil})
    Process.sleep(200)

    stopped = stop_both(host, other)

    assert stopped.host.players.on_other.x > 0.0
    assert stopped.host.players.on_host.x > 0.0
    assert stopped.host == stopped.other
    assert stopped.rollbacks > 0
  end

  test "two worlds playing with rollback over a link end at the same state" do
    {:ok, host} = World.start_link(game: Race, hz: 100)
    {:ok, listener} = Cauldron2D.Link.listen(host)
    {:ok, link} = Cauldron2D.Link.connect({127, 0, 0, 1}, Cauldron2D.Link.port(listener))
    {:ok, other} = World.start_link(game: Race, follow: link, rollback: true)

    :ok = World.join(host, :on_host, %{})
    :ok = World.join(other, :on_other, %{speed: 2.0})
    Process.sleep(100)

    World.input(host, :on_host, %{held: MapSet.new([:forward]), aim: nil})
    World.input(other, :on_other, %{held: MapSet.new([:forward]), aim: nil})
    Process.sleep(300)

    stopped = stop_both(host, other)

    assert stopped.host.players.on_other.x > 0.0
    assert stopped.host == stopped.other
  end

  defp stop_both(host, other) do
    :sys.suspend(host)
    :sys.suspend(other)
    host_world = :sys.get_state(host)
    other_world = :sys.get_state(other)
    frame = min(host_world.steps, other_world.steps)

    %{
      host: state_at(host_world, frame),
      other: state_at(other_world, frame),
      rollbacks: host_world.rollback.rollbacks + other_world.rollback.rollbacks
    }
  end

  defp state_at(world, frame) when world.steps == frame, do: world.state
  defp state_at(world, frame), do: Map.fetch!(world.rollback.states, frame)
end
