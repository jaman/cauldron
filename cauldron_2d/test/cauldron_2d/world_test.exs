defmodule Cauldron2D.WorldTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Player, Replay, World}
  alias Cauldron2D.TestGames.Race
  alias Cauldron2D.World.Presence

  defp start(opts \\ []) do
    {:ok, world} = World.start_link([game: Race, hz: 100] ++ opts)
    world
  end

  defp frame do
    receive do
      {:cauldron_frame, frame} -> frame
    after
      500 -> flunk("no frame arrived")
    end
  end

  defp flush_frames do
    receive do
      {:cauldron_frame, _} -> flush_frames()
    after
      0 -> :ok
    end
  end

  test "the world says which game it runs, so a view can be read from a snapshot by anyone" do
    world = start()
    :ok = Player.join(world, :alice, %{})
    game = World.game(world)
    assert game == Cauldron2D.TestGames.Race
    assert %{me: 0.0, others: 0} = game.view(World.snapshot(world), :alice)
  end

  test "a joined player receives its own view every tick" do
    world = start()
    :ok = Player.join(world, :alice, %{})

    assert %{tick: tick, view: %{me: me, others: 0}} = frame()
    assert me == 0.0
    assert %{tick: next} = frame()
    assert next == tick + 1
  end

  test "input is applied at the next tick and shows in the view" do
    world = start()
    :ok = Player.join(world, :alice, %{speed: 100.0})
    Player.input(world, :alice, %{held: MapSet.new([:forward]), aim: nil})
    Process.sleep(60)
    flush_frames()
    assert %{view: %{me: x}} = frame()
    assert x > 0.0
  end

  test "views are per player and a full world refuses a third" do
    world = start()
    :ok = Player.join(world, :alice, %{})

    bob =
      spawn_link(fn ->
        Player.join(world, :bob, %{})
        Process.sleep(:infinity)
      end)

    Process.sleep(30)
    flush_frames()
    assert %{view: %{others: 1}} = frame()
    assert {:error, :full} = Player.join(world, :carol, %{})
    Process.exit(bob, :kill)
  end

  test "a player whose process dies leaves the world" do
    world = start()
    :ok = Player.join(world, :alice, %{})

    bob =
      spawn(fn ->
        Player.join(world, :bob, %{})
        Process.sleep(:infinity)
      end)

    Process.sleep(30)
    Process.exit(bob, :kill)
    Process.sleep(30)
    flush_frames()
    assert %{view: %{others: 0}} = frame()
    assert World.players(world) == [:alice]
  end

  test "events drained each tick reach every player" do
    world = start()
    :ok = Player.join(world, :alice, %{})
    Process.sleep(120)
    frames = collect_frames([])

    assert Enum.any?(frames, fn %{events: events} ->
             Enum.any?(events, &match?({:beep, _}, &1))
           end)
  end

  defp collect_frames(acc) do
    receive do
      {:cauldron_frame, frame} -> collect_frames([frame | acc])
    after
      0 -> acc
    end
  end

  test "joins and leaves are told to whoever subscribed to presence" do
    Presence.subscribe()
    world = start()
    :ok = Player.join(world, :alice, %{})
    assert_receive {:cauldron_players, ^world, :joined, :alice}
    :ok = Player.leave(world, :alice)
    assert_receive {:cauldron_players, ^world, :left, :alice}
    Presence.unsubscribe()
    :ok = Player.join(world, :bob, %{})
    refute_receive {:cauldron_players, _, _, _}, 50
  end

  test "leaving stops the frames" do
    world = start()
    :ok = Player.join(world, :alice, %{})
    :ok = Player.leave(world, :alice)
    Process.sleep(30)
    flush_frames()
    refute_receive {:cauldron_frame, _}, 50
  end

  test "a recorded world replays to the same state" do
    world = start(record: true, game_opts: [seed: 7])
    :ok = Player.join(world, :alice, %{speed: 3.0})
    Process.sleep(25)
    Player.input(world, :alice, %{held: MapSet.new([:forward]), aim: nil})
    Process.sleep(60)
    Player.input(world, :alice, %{held: MapSet.new(), aim: nil})
    Process.sleep(30)

    snapshot = World.snapshot(world)
    replay = World.replay(world)

    replayed = Replay.run(replay, Race, [seed: 7], 1 / 100)
    assert replayed.players[:alice].x == snapshot.players[:alice].x
    assert replayed.ticks == snapshot.ticks
  end

  test "a subscriber that is not a player gets each tick's events" do
    world = start()
    :ok = World.Events.subscribe(world)
    assert {:error, :no_such_world} = World.Events.subscribe(:no_such_world_here)
    assert_receive {:cauldron_events, ^world, tick, [{:beep, _} | _]}, 500
    assert is_integer(tick)
    :ok = World.Events.unsubscribe(world)
    Process.sleep(50)
    flush_events()
    refute_receive {:cauldron_events, _, _, _}, 200
  end

  defp flush_events do
    receive do
      {:cauldron_events, _, _, _} -> flush_events()
    after
      0 -> :ok
    end
  end

  test "stats say how many players there are and how long the recent ticks took" do
    world = start()
    :ok = Player.join(world, :alice, %{})
    Process.sleep(120)
    stats = World.stats(world)
    assert stats.players == 1
    assert stats.hz == 100
    assert stats.steps > 5
    assert stats.ticks > 5 and stats.ticks <= 256
    assert stats.tick_us.max >= stats.tick_us.p95 and stats.tick_us.p95 >= stats.tick_us.mean
    assert stats.tick_us.mean >= 0 and is_integer(stats.tick_us.max)
    assert stats.behind >= 0
  end
end
