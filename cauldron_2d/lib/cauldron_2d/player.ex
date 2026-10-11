defmodule Cauldron2D.Player do
  @moduledoc """
  A player's side of a `Cauldron2D.World`: join, send input, receive frames, leave.

  Anything that runs in a process can be a player — a terminal session, a computer
  player, a test.

      :ok = Cauldron2D.Player.join(world, :alice, %{username: "alice"})
      Cauldron2D.Player.input(world, :alice, Cauldron2D.Input.state(input))

      receive do
        {:cauldron_frame, %{tick: tick, view: view, events: events}} -> ...
      end

  Frames arrive once per tick for as long as the player is joined, or as often as the
  player asked with `join/4`'s `frames:` or `frames/3`, each carrying the events since
  the one before. Leaving, or the process exiting, stops them.
  """

  alias Cauldron2D.World

  @doc """
  Join `world` as `id` from the calling process; `frames:` is how often it is sent
  frames — `true` every tick, a number a second, `false` none, for a player that only
  sends input (`Cauldron2D.World.join/4`). `{:error, :taken}` when
  another process already plays as `id`.
  """
  @spec join(GenServer.server(), World.player_id(), map(), keyword()) :: :ok | {:error, term()}
  defdelegate join(world, id, props, opts \\ []), to: World

  @doc "Send what the player is doing now; applied before the next tick."
  @spec input(GenServer.server(), World.player_id(), Cauldron2D.Input.state()) :: :ok
  defdelegate input(world, id, input), to: World

  @doc "Change how often the player is sent frames: `true`, a number a second, or `false`."
  @spec frames(GenServer.server(), World.player_id(), boolean() | number()) :: :ok
  defdelegate frames(world, id, rate), to: World

  @doc "Leave `world`."
  @spec leave(GenServer.server(), World.player_id()) :: :ok
  defdelegate leave(world, id), to: World
end
