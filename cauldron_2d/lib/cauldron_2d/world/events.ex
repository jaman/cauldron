defmodule Cauldron2D.World.Events do
  @moduledoc """
  A world's events, told each tick to processes that are not its players — a
  recorder, a referee, a bot that reads the game without playing it.

      Cauldron2D.World.Events.subscribe(world)
      receive do
        {:cauldron_events, world, tick, events} -> ...
      end

  A subscriber gets one message per tick that had events, with the same list the
  players get in their frames, until it unsubscribes or exits; `world` is the world's
  pid, and `subscribe/1` takes a pid or a registered name.
  """

  @registry __MODULE__

  @doc false
  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: @registry)

  @doc "Receive `world`'s events in the calling process."
  @spec subscribe(GenServer.server()) :: :ok | {:error, :no_such_world}
  def subscribe(world) do
    case GenServer.whereis(world) do
      nil ->
        {:error, :no_such_world}

      pid ->
        Registry.register(@registry, pid, nil)
        :ok
    end
  end

  @doc "Stop receiving them."
  @spec unsubscribe(GenServer.server()) :: :ok
  def unsubscribe(world) do
    case GenServer.whereis(world) do
      nil -> :ok
      pid -> Registry.unregister(@registry, pid)
    end
  end

  @doc "Tell `world`'s subscribers the tick's events; nothing is sent for an empty list."
  @spec broadcast(pid(), non_neg_integer(), list()) :: :ok
  def broadcast(_world, _tick, []), do: :ok

  def broadcast(world, tick, events) do
    Registry.dispatch(@registry, world, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:cauldron_events, world, tick, events})
    end)
  end
end
