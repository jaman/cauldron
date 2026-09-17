defmodule Cauldron2D.World.Presence do
  @moduledoc """
  Who comes and goes in every world on the node, told to whoever asks.

      Cauldron2D.World.Presence.subscribe()
      receive do
        {:cauldron_players, world, :joined, id} -> ...
        {:cauldron_players, world, :left, id} -> ...
      end

  A subscribed process is sent a message for every join and leave in every
  `Cauldron2D.World` until it unsubscribes or exits; `world` is the world's pid.
  """

  @registry __MODULE__

  @doc false
  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: @registry)

  @doc "Receive every world's joins and leaves in the calling process."
  @spec subscribe() :: :ok
  def subscribe do
    Registry.register(@registry, :players, nil)
    :ok
  end

  @doc "Stop receiving them."
  @spec unsubscribe() :: :ok
  def unsubscribe, do: Registry.unregister(@registry, :players)

  @doc "Tell every subscriber that `id` joined or left the world `world`."
  @spec broadcast(pid(), :joined | :left, term()) :: :ok
  def broadcast(world, change, id) when change in [:joined, :left] do
    Registry.dispatch(@registry, :players, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:cauldron_players, world, change, id})
    end)
  end
end
