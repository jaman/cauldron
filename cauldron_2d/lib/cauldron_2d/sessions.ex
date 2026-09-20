defmodule Cauldron2D.Sessions do
  @moduledoc """
  Who is logged in on the node, by whatever kind of client, told to whoever asks.

      Cauldron2D.Sessions.track("alice", :terminal)
      Cauldron2D.Sessions.list()
      #=> [%{id: "alice", kind: :terminal, since: 1789718400, pid: #PID<0.312.0>}]
      Cauldron2D.Sessions.subscribe()
      receive do
        {:cauldron_sessions, :opened, session} -> ...
        {:cauldron_sessions, :closed, session} -> ...
      end

  A session is the calling process — a client on an ssh connection, a page in a
  browser — listed from `track/2` until the process exits or tracks again. `kind` is
  whatever the client calls itself. A subscribed process hears every opening and closing
  until it unsubscribes or exits.
  """

  use GenServer

  @type session :: %{id: term(), kind: atom(), since: integer(), pid: pid()}

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "List the calling process as a session of `id`, of this `kind`, until it exits."
  @spec track(term(), atom()) :: :ok
  def track(id, kind) when is_atom(kind), do: GenServer.call(__MODULE__, {:track, id, kind})

  @doc "Every session on the node, oldest first."
  @spec list() :: [session()]
  def list, do: GenServer.call(__MODULE__, :list)

  @doc "Receive every opening and closing in the calling process."
  @spec subscribe() :: :ok
  def subscribe, do: GenServer.call(__MODULE__, :subscribe)

  @doc "Stop receiving them."
  @spec unsubscribe() :: :ok
  def unsubscribe, do: GenServer.call(__MODULE__, :unsubscribe)

  @impl true
  def init(_opts), do: {:ok, %{sessions: %{}, monitors: %{}, watchers: %{}}}

  @impl true
  def handle_call({:track, id, kind}, {pid, _tag}, state) do
    state = closed(state, pid)
    session = %{id: id, kind: kind, since: System.system_time(:second), pid: pid}
    tell(state, :opened, session)

    {:reply, :ok,
     state
     |> put_in([:sessions, pid], session)
     |> put_in([:monitors, pid], {Process.monitor(pid), :erlang.unique_integer([:monotonic])})}
  end

  def handle_call(:list, _from, state) do
    sessions =
      state.sessions
      |> Enum.sort_by(fn {pid, _session} -> elem(state.monitors[pid], 1) end)
      |> Enum.map(fn {_pid, session} -> session end)

    {:reply, sessions, state}
  end

  def handle_call(:subscribe, {pid, _tag}, state) do
    ref = Process.monitor(pid)
    {:reply, :ok, put_in(state, [:watchers, pid], ref)}
  end

  def handle_call(:unsubscribe, {pid, _tag}, state) do
    {ref, watchers} = Map.pop(state.watchers, pid)
    if ref, do: Process.demonitor(ref, [:flush])
    {:reply, :ok, %{state | watchers: watchers}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, state |> closed(pid) |> Map.update!(:watchers, &Map.delete(&1, pid))}
  end

  defp closed(state, pid) do
    case Map.pop(state.sessions, pid) do
      {nil, _sessions} ->
        state

      {session, sessions} ->
        {{ref, _seq}, monitors} = Map.pop(state.monitors, pid)
        Process.demonitor(ref, [:flush])
        tell(state, :closed, session)
        %{state | sessions: sessions, monitors: monitors}
    end
  end

  defp tell(state, change, session) do
    for {watcher, _ref} <- state.watchers,
        do: send(watcher, {:cauldron_sessions, change, session})

    :ok
  end
end
