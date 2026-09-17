defmodule Cauldron2D.Net.Link.Local do
  @moduledoc """
  A player's connection to a world reachable as a process — on this node, or
  on a node this one is connected to — through `Cauldron2D.Net.Session`, so the frames
  arrive in the same shape a `Cauldron2D.Net.Link.Socket` delivers.

      {:ok, link} = Cauldron2D.Net.Link.Local.start_link(game: MyGame.Client, world: pid, name: "alice", props: %{}, owner: self())

  The owner receives `{:cauldron_link, :sheet, sheet, png}` once, `{:cauldron_link, :map, map}`
  once, `{:cauldron_link, :frame, frame}` each tick and `{:cauldron_link, :closed, reason}`
  when the world goes. Sound plays through `:sink` (default `TuningFork.Sink.Speaker`),
  on this machine. `input/2`, `levels/3` and `leave/1` are what the player does.
  """

  use GenServer

  alias Cauldron2D.Net.{Session, Sheet}
  alias Cauldron2D.Net.Wire

  @doc "Join `:world` as `:name` with `:props` for `:game`, reporting to `:owner`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "What the player holds and aims at, as `Cauldron2D.Wx.Input.state/1` gives it."
  @spec input(GenServer.server(), %{held: [String.t()], aim: [number()] | nil}) :: :ok
  def input(link, state), do: GenServer.cast(link, {:input, state})

  @doc "The effects and music levels."
  @spec levels(GenServer.server(), number(), number()) :: :ok
  def levels(link, sfx, music), do: GenServer.cast(link, {:levels, sfx, music})

  @doc "Pause or resume a world of the player's own; nothing for a shared one."
  @spec pause(GenServer.server()) :: :ok
  def pause(link), do: GenServer.cast(link, :pause)

  @doc "Leave the world and stop."
  @spec leave(GenServer.server()) :: :ok
  def leave(link), do: GenServer.stop(link, :normal)

  @impl GenServer
  def init(opts) do
    game = Keyword.fetch!(opts, :game)
    owner = Keyword.fetch!(opts, :owner)
    world = Keyword.fetch!(opts, :world)
    sink = Keyword.get(opts, :sink, TuningFork.Sink.Speaker)
    Process.monitor(owner)
    if is_pid(world), do: Process.monitor(world)

    case Session.join(game, world, Keyword.fetch!(opts, :name), Keyword.get(opts, :props, %{}),
           sink: sink
         ) do
      {:ok, session, pushes} ->
        send(
          owner,
          {:cauldron_link, :sheet, Wire.sheet(sheet_payload(pushes)),
           Sheet.cached(game.atlas()).png}
        )

        {:ok, %{session: session, owner: owner}}

      {:error, reason} ->
        send(owner, {:cauldron_link, :refused, reason})
        :ignore
    end
  end

  defp sheet_payload(pushes), do: pushes |> Enum.find(&match?({"sheet", _}, &1)) |> elem(1)

  @impl GenServer
  def handle_cast({:input, %{held: held, aim: aim}}, state),
    do: {:noreply, %{state | session: Session.input(state.session, held, aim)}}

  def handle_cast({:levels, sfx, music}, state),
    do: {:noreply, %{state | session: Session.levels(state.session, sfx, music)}}

  def handle_cast(:pause, state),
    do: {:noreply, %{state | session: Session.toggle_pause(state.session)}}

  @impl GenServer
  def handle_info({:cauldron_frame, message}, state) do
    {session, pushes} = Session.frame(state.session, message)

    for {event, payload} <- pushes do
      case event do
        "map" -> send(state.owner, {:cauldron_link, :map, Wire.map(payload)})
        "frame" -> send(state.owner, {:cauldron_link, :frame, Wire.frame(payload)})
      end
    end

    {:noreply, %{state | session: session}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{owner: pid} = state),
    do: {:stop, {:shutdown, {:owner_gone, reason}}, state}

  def handle_info({:DOWN, _ref, :process, _world, reason}, state) do
    send(state.owner, {:cauldron_link, :closed, reason})
    {:stop, :normal, %{state | session: %{state.session | world: nil}}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{session: %{world: nil}}), do: :ok

  def terminate(_reason, %{session: session}) do
    Session.leave(session)
  catch
    :exit, _gone -> :ok
  end
end
