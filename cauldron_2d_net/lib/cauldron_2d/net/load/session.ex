defmodule Cauldron2D.Net.Load.Session do
  @moduledoc """
  One session of a load test: a player or a watcher on a server's arena over the same
  WebSocket a browser or the desktop uses (`Cauldron2D.Net.Link.Socket`), counting the
  frames it gets. A player changes what it holds five times a second, at random from
  the actions it was given.

      {:ok, session} = Cauldron2D.Net.Load.Session.start_link(url: url, token: token, arena: "pit", kind: :player, actions: ["left", "right", "fire"])
      Cauldron2D.Net.Load.Session.report(session)

  `report/1` returns `%{joined: true | false | nil, reason: term, frames: n, recent: n,
  gap_ms: n, join_ms: n | nil, alive_ms: n}`: whether the join has succeeded (`nil`
  while pending), the reason of a refusal or a closed connection, the frames received
  altogether and since the last report, the longest wait between two frames since the
  last report in milliseconds, how long the join took, and how long the session has
  been in the arena.
  """

  use GenServer

  alias Cauldron2D.Net.Link.Socket

  @steer_ms 200

  @type report :: %{
          joined: boolean() | nil,
          reason: term(),
          frames: non_neg_integer(),
          recent: non_neg_integer(),
          gap_ms: non_neg_integer(),
          join_ms: non_neg_integer() | nil,
          alive_ms: non_neg_integer()
        }

  @doc "Start a session; `:url`, `:token`, `:arena` (its id as it writes), `:kind` (`:player` or `:watcher`) and `:actions` are required, `:topic` is the channel's prefix (default `\"world\"`), `:audio` `:personal` (default) or `:off` to ask the server for no sound."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "How the session is doing, and reset its recent frame count and longest gap."
  @spec report(GenServer.server()) :: report()
  def report(session), do: GenServer.call(session, :report)

  @doc "Leave the arena and stop."
  @spec stop(GenServer.server()) :: :ok
  def stop(session), do: GenServer.stop(session, :normal)

  @impl GenServer
  def init(opts) do
    kind = Keyword.fetch!(opts, :kind)
    params = if kind == :watcher, do: %{"spectate" => true}, else: %{}

    params =
      if Keyword.get(opts, :audio, :personal) == :off,
        do: Map.put(params, "audio", false),
        else: params

    topic = Keyword.get(opts, :topic, "world")

    {:ok, link} =
      Socket.start_link(
        url: Keyword.fetch!(opts, :url),
        token: Keyword.fetch!(opts, :token),
        topic: "#{topic}:#{Keyword.fetch!(opts, :arena)}",
        params: params,
        owner: self()
      )

    {:ok,
     %{
       link: link,
       kind: kind,
       actions: Keyword.fetch!(opts, :actions),
       started: now(),
       joined: nil,
       reason: nil,
       frames: 0,
       recent: 0,
       last: nil,
       gap: 0,
       join_ms: nil,
       joined_at: nil
     }}
  end

  @impl GenServer
  def handle_call(:report, _from, state) do
    alive_ms = if state.joined_at, do: now() - state.joined_at, else: 0

    report = %{
      joined: state.joined,
      reason: state.reason,
      frames: state.frames,
      recent: state.recent,
      gap_ms: state.gap,
      join_ms: state.join_ms,
      alive_ms: alive_ms
    }

    {:reply, report, %{state | recent: 0, gap: 0}}
  end

  @impl GenServer
  def handle_info({:cauldron_link, :joined}, state) do
    if state.kind == :player and state.actions != [],
      do: Process.send_after(self(), :steer, @steer_ms)

    {:noreply, %{state | joined: true, join_ms: now() - state.started, joined_at: now()}}
  end

  def handle_info({:cauldron_link, :frame, _frame}, state) do
    at = now()
    gap = if state.last, do: max(state.gap, at - state.last), else: state.gap
    {:noreply, %{state | frames: state.frames + 1, recent: state.recent + 1, last: at, gap: gap}}
  end

  def handle_info({:cauldron_link, :refused, reason}, state),
    do: {:noreply, %{state | joined: false, reason: reason}}

  def handle_info({:cauldron_link, :closed, reason}, state),
    do: {:noreply, %{state | joined: false, reason: reason}}

  def handle_info(:steer, %{joined: true} = state) do
    Process.send_after(self(), :steer, @steer_ms)

    Socket.input(state.link, %{
      held: Enum.take_random(state.actions, :rand.uniform(min(3, length(state.actions)))),
      aim: nil
    })

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{link: link}) do
    if Process.alive?(link), do: Socket.leave(link)
    :ok
  end

  defp now, do: System.monotonic_time(:millisecond)
end
