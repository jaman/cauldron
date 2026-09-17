defmodule Cauldron2D.Net.LoadTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Net.Load

  defp interval(overrides) do
    arena = %{
      name: "Pit",
      players: 3,
      hz: 50,
      steps: 0,
      ticks: 256,
      tick_us: %{mean: 3000, p95: 6000, max: 9000},
      behind: 2
    }

    Map.merge(
      %{
        hz: 50,
        fps: %{mean: 50.0, min: 49.0},
        gap_ms: 40,
        arenas: [arena],
        sessions: 10,
        joined: 10,
        node: %{}
      },
      overrides
    )
  end

  test "an interval within budget is not degraded" do
    assert Load.degraded(interval(%{})) == []
  end

  test "a world over its tick budget at the 95th percentile, or behind on over 5% of ticks, degrades the run and says which" do
    slow = %{
      name: "Alrin",
      players: 27,
      hz: 50,
      steps: 0,
      ticks: 256,
      tick_us: %{mean: 9000, p95: 21_000, max: 50_000},
      behind: 3
    }

    assert ["Alrin's ticks run 21.0 ms at the 95th percentile, over the 20.0 ms budget"] =
             Load.degraded(interval(%{arenas: [slow]}))

    jittery = %{slow | tick_us: %{mean: 3000, p95: 6000, max: 9000}, behind: 40}
    assert [] = Load.degraded(interval(%{arenas: [jittery]}))
    behind = %{jittery | behind: 60}
    assert ["Alrin ran behind on 23% of its ticks"] = Load.degraded(interval(%{arenas: [behind]}))
  end

  test "a session starved of frames degrades the run" do
    assert ["a session got 36.7 frames a second of 50"] =
             Load.degraded(interval(%{fps: %{mean: 51.0, min: 36.7}}))

    assert ["a session waited 1200 ms for a frame"] = Load.degraded(interval(%{gap_ms: 1200}))
  end

  test "stop with no run in progress is nothing" do
    assert Load.stop() == :ok
  end
end
