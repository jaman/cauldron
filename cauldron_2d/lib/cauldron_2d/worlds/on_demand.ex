defmodule Cauldron2D.Worlds.OnDemand do
  @moduledoc """
  The name registry behind `Cauldron2D.Worlds.world_name/1`:
  `{:via, Cauldron2D.Worlds.OnDemand, id}` resolves to world `id`, starting the
  world when it is not running. An id no world is registered for resolves to `:undefined`.
  """

  alias Cauldron2D.Worlds

  @doc false
  @spec register_name(Worlds.id(), pid()) :: :yes | :no
  def register_name(id, pid),
    do: Registry.register_name({Cauldron2D.Worlds.Registry, {:world, id}}, pid)

  @doc false
  @spec unregister_name(Worlds.id()) :: :ok
  def unregister_name(id),
    do: Registry.unregister_name({Cauldron2D.Worlds.Registry, {:world, id}})

  @doc false
  @spec whereis_name(Worlds.id()) :: pid() | :undefined
  def whereis_name(id) do
    case Worlds.running(id) do
      nil -> started(id)
      pid -> pid
    end
  end

  @doc false
  @spec send(Worlds.id(), term()) :: term()
  def send(id, message) do
    case whereis_name(id) do
      :undefined -> :erlang.error(:badarg, [id, message])
      pid -> Kernel.send(pid, message)
    end
  end

  defp started(id) do
    case Worlds.start(id) do
      {:ok, pid} when is_pid(pid) -> pid
      _not_started -> :undefined
    end
  end
end
