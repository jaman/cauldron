defmodule Cauldron2D.StatsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Arenas, Stats}
  alias Cauldron2D.TestGames.Race

  test "every running arena's world stats by name, and the node's" do
    :ok = Arenas.register(:stats_arena, game: Race)
    {:ok, _} = Arenas.start(:stats_arena)

    assert [%{name: "stats_arena", players: 0, hz: 50, steps: _, tick_us: %{mean: _}}] =
             Stats.arenas()

    assert %{processes: p, memory_mb: m, run_queue: _, schedulers: s, busy: busy} = Stats.node()
    assert p > 0 and m > 0 and s > 0 and busy >= 0.0
    Arenas.close(:stats_arena)
  end
end
