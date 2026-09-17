defmodule Cauldron2D.WorldModesTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Player, World}
  alias Cauldron2D.TestGames.Race

  defp frame do
    receive do
      {:cauldron_frame, frame} -> frame
    after
      500 -> flunk("no frame arrived")
    end
  end

  defp no_frame(ms) do
    receive do
      {:cauldron_frame, frame} -> flunk("a frame arrived: #{inspect(frame)}")
    after
      ms -> :ok
    end
  end

  test "a world stepping on input runs one step per input and none otherwise" do
    {:ok, world} = World.start_link(game: Race, hz: 10, tick: :on_input)
    :ok = Player.join(world, :alice, %{speed: 10.0})
    no_frame(150)

    Player.input(world, :alice, %{held: MapSet.new([:forward]), aim: nil})
    assert %{tick: 1, view: %{me: me}} = frame()
    assert_in_delta me, 1.0, 0.001
    no_frame(150)

    Player.input(world, :alice, %{held: MapSet.new(), aim: nil})
    assert %{tick: 2} = frame()
    assert World.stats(world).steps == 2
  end

  test "a paused world sends no frames and owes no steps when it resumes" do
    {:ok, world} = World.start_link(game: Race, hz: 100)
    :ok = Player.join(world, :alice, %{})
    frame()

    :ok = World.pause(world)
    assert World.paused?(world)
    Process.sleep(30)

    receive do
      {:cauldron_frame, _} -> :ok
    after
      0 -> :ok
    end

    no_frame(80)
    steps = World.stats(world).steps

    :ok = World.resume(world)
    refute World.paused?(world)
    first = frame()
    assert first.tick - steps <= 2
  end

  test "input sent while paused is applied on resume" do
    {:ok, world} = World.start_link(game: Race, hz: 100)
    :ok = Player.join(world, :alice, %{speed: 5.0})
    :ok = World.pause(world)
    Player.input(world, :alice, %{held: MapSet.new([:forward]), aim: nil})
    Process.sleep(30)
    assert World.snapshot(world).players.alice.x == 0.0
    :ok = World.resume(world)
    Process.sleep(60)
    assert World.snapshot(world).players.alice.x > 0.0
  end

  test "a world can start from a state instead of the game's init" do
    {:ok, world} =
      World.start_link(
        game: Race,
        hz: 100,
        state: %{players: %{}, events: [], seed: 99, ticks: 40}
      )

    assert World.snapshot(world).seed == 99
    assert World.snapshot(world).ticks >= 40
  end
end
