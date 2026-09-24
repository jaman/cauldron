defmodule Cauldron2D.StatsTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.{Stats, Worlds}
  alias Cauldron2D.TestGames.Race

  test "every running world's stats by name, and the node's" do
    :ok = Worlds.register(:stats_world, game: Race)
    {:ok, _} = Worlds.start(:stats_world)

    assert [%{name: "stats_world", players: 0, hz: 50, steps: _, tick_us: %{mean: _}}] =
             Stats.worlds()

    assert %{processes: p, memory_mb: m, run_queue: _, schedulers: s, busy: busy} = Stats.node()
    assert p > 0 and m > 0 and s > 0 and busy >= 0.0
    Worlds.close(:stats_world)
  end
end
