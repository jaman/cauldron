defmodule Cauldron2D.Stats do
  @moduledoc """
  How this node is keeping up: every running arena's world as `Cauldron2D.World.stats/1`
  gives it, and the node it runs on.

      Cauldron2D.Stats.arenas()
      Cauldron2D.Stats.node()
  """

  alias Cauldron2D.{Arenas, World}

  @type arena :: %{
          name: String.t(),
          players: non_neg_integer(),
          hz: number(),
          steps: non_neg_integer(),
          ticks: non_neg_integer(),
          tick_us: %{mean: non_neg_integer(), p95: non_neg_integer(), max: non_neg_integer()},
          behind: non_neg_integer()
        }
  @type node_stats :: %{
          processes: non_neg_integer(),
          memory_mb: non_neg_integer(),
          run_queue: non_neg_integer(),
          schedulers: pos_integer(),
          busy: float()
        }

  @doc "Every running arena's world stats, with the arena's id as its `:name`, sorted."
  @spec arenas() :: [arena()]
  def arenas do
    for id <- Enum.sort_by(Arenas.running_ids(), &to_string/1),
        pid = Arenas.running(id),
        stats = world_stats(pid),
        do: Map.put(stats, :name, to_string(id))
  end

  @doc """
  The processes, the memory in megabytes, the run queue, the schedulers of this node,
  and `busy`, the share of the schedulers' time spent running since the last call,
  0.0 to 1.0 (0.0 on the first call).
  """
  @spec node() :: node_stats()
  def node do
    %{
      processes: :erlang.system_info(:process_count),
      memory_mb: div(:erlang.memory(:total), 1_048_576),
      run_queue: :erlang.statistics(:run_queue),
      schedulers: :erlang.system_info(:schedulers_online),
      busy: busy()
    }
  end

  defp busy do
    :erlang.system_flag(:scheduler_wall_time, true)
    now = :erlang.statistics(:scheduler_wall_time) |> Enum.sort()
    before = :persistent_term.get({__MODULE__, :wall_time}, nil)
    :persistent_term.put({__MODULE__, :wall_time}, now)

    case before do
      nil ->
        0.0

      before ->
        {active, total} =
          Enum.zip(before, now)
          |> Enum.reduce({0, 0}, fn {{_, a0, t0}, {_, a1, t1}}, {active, total} ->
            {active + (a1 - a0), total + (t1 - t0)}
          end)

        if total == 0, do: 0.0, else: Float.round(active / total, 3)
    end
  end

  defp world_stats(pid) do
    World.stats(pid)
  catch
    :exit, _stopped_meanwhile -> nil
  end
end
