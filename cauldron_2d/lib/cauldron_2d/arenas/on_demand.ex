defmodule Cauldron2D.Arenas.OnDemand do
  @moduledoc """
  The name registry behind `Cauldron2D.Arenas.world_name/1`:
  `{:via, Cauldron2D.Arenas.OnDemand, id}` resolves to arena `id`'s world, starting the
  arena when it is not running. An id no arena is registered for resolves to `:undefined`.
  """

  alias Cauldron2D.Arenas

  @doc false
  @spec register_name(Arenas.id(), pid()) :: :yes | :no
  def register_name(id, pid),
    do: Registry.register_name({Cauldron2D.Arenas.Registry, {:world, id}}, pid)

  @doc false
  @spec unregister_name(Arenas.id()) :: :ok
  def unregister_name(id),
    do: Registry.unregister_name({Cauldron2D.Arenas.Registry, {:world, id}})

  @doc false
  @spec whereis_name(Arenas.id()) :: pid() | :undefined
  def whereis_name(id) do
    case Arenas.running(id) do
      nil -> started(id)
      pid -> pid
    end
  end

  @doc false
  @spec send(Arenas.id(), term()) :: term()
  def send(id, message) do
    case whereis_name(id) do
      :undefined -> :erlang.error(:badarg, [id, message])
      pid -> Kernel.send(pid, message)
    end
  end

  defp started(id) do
    case Arenas.start(id) do
      {:ok, pid} when is_pid(pid) -> pid
      _not_started -> :undefined
    end
  end
end
