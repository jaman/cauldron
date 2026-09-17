defmodule Cauldron2D.ArenasTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Arenas, Player, World}
  alias Cauldron2D.TestGames.Race

  defmodule Companion do
    @moduledoc false
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl true
    def init(opts) do
      send(Keyword.fetch!(opts, :test), {:companion, Keyword.fetch!(opts, :number), self()})
      {:ok, opts}
    end
  end

  setup do
    on_exit(fn -> for id <- Arenas.ids(), do: Arenas.close(id) end)
    :ok
  end

  test "a registered arena is listed without running, and starts on the first use of its world's name" do
    :ok =
      Arenas.register(:pit,
        game: Race,
        name: "The Pit",
        map: "pit",
        note: "two racers",
        kind: {"race", {0, 200, 0}},
        teams: [1, 2]
      )

    assert [
             %{
               id: :pit,
               name: "The Pit",
               map: "pit",
               note: "two racers",
               kind: {"race", _},
               teams: [1, 2],
               players: 0,
               world: world
             }
           ] = Arenas.list()

    refute Arenas.running?(:pit)

    :ok = Player.join(world, :alice, %{})
    assert Arenas.running?(:pit)
    assert Arenas.humans(:pit) == [:alice]
    assert [%{players: 1, humans: [:alice]}] = Arenas.list()
    assert_receive {:cauldron_frame, _}, 500
  end

  test "the arena's children start with the world, get its name and the humans, and are seated again when missing" do
    test = self()

    :ok =
      Arenas.register(:manned,
        game: Race,
        children: fn %{id: :manned, world: world, humans: humans} ->
          for n <- 1..(2 - humans)//1,
              do: %{
                id: {:companion, n},
                start: {Companion, :start_link, [[test: test, number: n, world: world]]},
                restart: :transient
              }
        end
      )

    {:ok, _world} = Arenas.start(:manned)
    assert_receive {:companion, 1, first}
    assert_receive {:companion, 2, _second}

    GenServer.stop(first, :normal)
    :ok = Arenas.reseat(:manned)
    assert_receive {:companion, 1, again}
    assert again != first
    refute_receive {:companion, 2, _}, 50
  end

  test "stopping keeps the registration, closing removes it, and a running world's players leave with it" do
    :ok = Arenas.register(:brief, game: Race)
    :ok = Player.join(Arenas.world_name(:brief), :bob, %{})
    world = Arenas.running(:brief)
    assert is_pid(world)
    :ok = Arenas.stop(:brief)
    refute Process.alive?(world)
    assert [%{id: :brief}] = Arenas.list()
    :ok = Arenas.close(:brief)
    assert Arenas.list() == []
    assert {:error, :unknown_arena} = Arenas.start(:brief)
  end

  test "the sweeper stops a world that has had no human for its idle time, and leaves a manned one alone" do
    :ok = Arenas.register(:idle, game: Race)
    :ok = Arenas.register(:busy, game: Race)
    {:ok, _} = Arenas.start(:idle)
    :ok = Player.join(Arenas.world_name(:busy), :carol, %{})
    {:ok, sweeper} = Arenas.Sweeper.start_link(idle_after: 0, every: :never, name: nil)
    :ok = Arenas.Sweeper.sweep(sweeper)
    refute Arenas.running?(:idle)
    assert Arenas.running?(:busy)
    GenServer.stop(sweeper)
  end

  test "listing a hundred arenas with large game options is a matter of milliseconds: the listing copies none of them" do
    big = :binary.copy(<<0>>, 2_000_000)

    for n <- 1..100,
        do:
          :ok =
            Arenas.register(:"big_#{n}",
              game: Race,
              game_opts: [map: big],
              name: "Big #{n}",
              map: "big"
            )

    {us, list} = :timer.tc(fn -> Arenas.list() end)
    assert length(list) == 100
    assert us < 20_000, "listing took #{div(us, 1000)} ms"
    refute Enum.any?(list, &Map.has_key?(&1, :game_opts))
  end

  test "the arena's world options reach the world" do
    :ok = Arenas.register(:fast, game: Race, game_opts: [seed: 7], hz: 200, tick: :on_input)
    {:ok, world} = Arenas.start(:fast)
    assert World.snapshot(world).seed == 7
    assert World.stats(world).hz == 200
  end
end
