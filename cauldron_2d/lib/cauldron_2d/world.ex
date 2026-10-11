defmodule Cauldron2D.World do
  @moduledoc """
  Runs a `Cauldron2D.Game` at a fixed tick and keeps its players supplied with views.

      {:ok, world} = Cauldron2D.World.start_link(game: MyGame, game_opts: [seed: 1], hz: 50)

  Players join from their own processes with `Cauldron2D.Player.join/3`; each tick the
  world applies the input they sent, steps the game once per due step, and sends every
  player whose frame is due `{:cauldron_frame, %{tick: n, view: view, events: events}}`
  — every tick, or as often as the player asked (`join/4`'s `:frames`, `frames/3`),
  the view built only for those frames. A player whose
  process exits is removed. Every join and leave is told to the subscribers of
  `Cauldron2D.World.Presence`, and each tick's events to those of
  `Cauldron2D.World.Events`. `stats/1` says how the world is keeping up.

  The next tick is timed only once the last has run, for when the next step falls due,
  so the world's mailbox never holds more than one tick: input sent while a slow tick
  runs is applied before the next step, however far the world falls behind. Steps
  more than `Cauldron2D.Loop`'s `:max_steps` behind are dropped, not owed.

  A world started with `tick: :on_input` has no clock: it runs one step, with `dt` of
  `1 / hz`, each time a player's input arrives, and sends views after it. That is the
  world for a turn-based game. `pause/1` stops a clocked world stepping until
  `resume/1`; time paused is not owed afterwards, and input sent meanwhile is applied
  on resume.

  ## Options

    * `:game` — the module implementing `Cauldron2D.Game`. Required
    * `:game_opts` — passed to its `init/1`. Default `[]`
    * `:state` — a game state to start from instead of calling `init/1`, as
      `snapshot/1` returned it. Default none
    * `:hz` — ticks per second, and the `dt` of a step. Default `50`
    * `:tick` — `:fixed`, stepping on the clock, or `:on_input`. Default `:fixed`
    * `:record` — keep a `Cauldron2D.Replay` of joins, leaves and input. Default `false`
    * `:name` — a GenServer name. Default none
  """

  use GenServer

  alias Cauldron2D.{Loop, Replay}
  alias Cauldron2D.World.{Events, Presence}

  @type player_id :: term()

  @typedoc """
  How the world is keeping up: the players present, the ticks a second it is set to,
  the steps run so far, and over the last #{256} ticks that ran a step — how many they
  were, the microseconds a tick took (stepping and sending every view) as a mean, a
  95th percentile and the longest, and `behind`, how many of them had more than one
  step due.
  """
  @type stats :: %{
          players: non_neg_integer(),
          hz: number(),
          steps: non_neg_integer(),
          ticks: non_neg_integer(),
          tick_us: %{mean: non_neg_integer(), p95: non_neg_integer(), max: non_neg_integer()},
          behind: non_neg_integer()
        }

  @window 256

  @doc "Start a world; see the module documentation for the options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Add the calling process as player `id`. `{:error, :taken}` when another process plays
  as `id`; any other `{:error, reason}` is the game's refusal.

  `:frames` is how often the player is sent a frame: `true` (default) after every tick
  that steps, a number for that many frames a second at most, or `false` for none — a
  second seat played from a process that already receives frames as another player. A
  frame carries the events of every step since the player's last frame. `:timeout` is how
  many milliseconds the world is given to take the player in, default `10_000`.
  """
  @spec join(GenServer.server(), player_id(), map(), keyword()) :: :ok | {:error, term()}
  def join(world, id, props, opts \\ []),
    do:
      GenServer.call(
        world,
        {:join, id, props, self(), Keyword.get(opts, :frames, true)},
        Keyword.get(opts, :timeout, 10_000)
      )

  @doc "Change how often player `id` is sent frames, as `join/4`'s `:frames` takes it."
  @spec frames(GenServer.server(), player_id(), boolean() | number()) :: :ok
  def frames(world, id, rate), do: GenServer.call(world, {:frames, id, rate})

  @doc "Remove player `id`."
  @spec leave(GenServer.server(), player_id()) :: :ok
  def leave(world, id), do: GenServer.call(world, {:leave, id})

  @doc "Send player `id`'s current input, applied before the next tick."
  @spec input(GenServer.server(), player_id(), Cauldron2D.Input.state()) :: :ok
  def input(world, id, input), do: GenServer.cast(world, {:input, id, input})

  @doc "The ids of the players present."
  @spec players(GenServer.server()) :: [player_id()]
  def players(world), do: GenServer.call(world, :players)

  @doc "The game's current state."
  @spec snapshot(GenServer.server()) :: term()
  def snapshot(world), do: GenServer.call(world, :snapshot)

  @doc "The game module the world runs."
  @spec game(GenServer.server()) :: module()
  def game(world), do: GenServer.call(world, :game)

  @doc "How the world is keeping up; see `t:stats/0`."
  @spec stats(GenServer.server()) :: stats()
  def stats(world), do: GenServer.call(world, :stats)

  @doc "Stop stepping until `resume/1`. Nothing for a world stepping on input."
  @spec pause(GenServer.server()) :: :ok
  def pause(world), do: GenServer.call(world, :pause)

  @doc "Step again, from now."
  @spec resume(GenServer.server()) :: :ok
  def resume(world), do: GenServer.call(world, :resume)

  @doc "Whether the world is paused."
  @spec paused?(GenServer.server()) :: boolean()
  def paused?(world), do: GenServer.call(world, :paused?)

  @doc "The replay recorded so far, or `nil` when the world was not started with `record: true`."
  @spec replay(GenServer.server()) :: Replay.t() | nil
  def replay(world), do: GenServer.call(world, :replay)

  @impl GenServer
  def init(opts) do
    game = Keyword.fetch!(opts, :game)
    hz = Keyword.get(opts, :hz, 50)
    tick = Keyword.get(opts, :tick, :fixed)
    loop = Loop.new(hz)
    if tick == :fixed, do: send(self(), :tick)

    {:ok,
     %{
       game: game,
       state:
         Keyword.get_lazy(opts, :state, fn -> game.init(Keyword.get(opts, :game_opts, [])) end),
       loop: loop,
       hz: hz,
       tick: tick,
       paused?: false,
       players: %{},
       pending: %{},
       steps: 0,
       timings: [],
       replay: if(Keyword.get(opts, :record, false), do: Replay.new())
     }}
  end

  @impl GenServer
  def handle_call({:join, id, props, pid, frames?}, _from, world) do
    if taken?(world, id, pid),
      do: {:reply, {:error, :taken}, world},
      else: joined(world, id, props, pid, frames?)
  end

  def handle_call({:leave, id}, _from, world), do: {:reply, :ok, remove(world, id)}

  def handle_call({:frames, id, rate}, _from, world) do
    case Map.fetch(world.players, id) do
      {:ok, player} -> {:reply, :ok, put_in(world.players[id], paced(player, rate, world))}
      :error -> {:reply, :ok, world}
    end
  end

  def handle_call(:players, _from, world), do: {:reply, Map.keys(world.players), world}
  def handle_call(:snapshot, _from, world), do: {:reply, world.state, world}
  def handle_call(:game, _from, world), do: {:reply, world.game, world}
  def handle_call(:replay, _from, world), do: {:reply, stamped(world.replay, world.steps), world}
  def handle_call(:stats, _from, world), do: {:reply, stats_of(world), world}
  def handle_call(:pause, _from, world), do: {:reply, :ok, %{world | paused?: true}}

  def handle_call(:resume, _from, world),
    do: {:reply, :ok, %{world | paused?: false, loop: Loop.new(world.hz)}}

  def handle_call(:paused?, _from, world), do: {:reply, world.paused?, world}

  defp taken?(world, id, pid) do
    case Map.get(world.players, id) do
      %{pid: ^pid} -> false
      %{pid: _held_by} -> true
      nil -> false
    end
  end

  defp joined(world, id, props, pid, frames?) do
    case world.game.join(world.state, id, props) do
      {:ok, state} ->
        monitor = Process.monitor(pid)
        player = paced(%{pid: pid, monitor: monitor, events: []}, frames?, world)
        players = Map.put(world.players, id, player)
        Presence.broadcast(self(), :joined, id)
        {:reply, :ok, %{world | state: state, players: players} |> record({:join, id, props})}

      {:error, reason} ->
        {:reply, {:error, reason}, world}
    end
  end

  @impl GenServer
  def handle_cast({:input, id, input}, world) do
    if Map.has_key?(world.players, id) do
      {:noreply, %{world | pending: Map.put(world.pending, id, input)} |> step_on_input()}
    else
      {:noreply, world}
    end
  end

  defp step_on_input(%{tick: :on_input} = world) do
    started = System.monotonic_time(:microsecond)
    world = world |> apply_pending() |> run(1, Loop.dt(world.loop)) |> broadcast()
    timed(world, System.monotonic_time(:microsecond) - started, 1)
  end

  defp step_on_input(world), do: world

  @impl GenServer
  def handle_info(:tick, %{paused?: true} = world) do
    {_due, loop} = Loop.advance(world.loop, Loop.now())
    Process.send_after(self(), :tick, max(1, round(Loop.dt(loop) * 1000)))
    {:noreply, %{world | loop: loop}}
  end

  def handle_info(:tick, world) do
    {due, loop} = Loop.advance(world.loop, Loop.now())
    world = %{world | loop: loop} |> apply_pending()
    world = if due > 0, do: stepped(world, due), else: world
    Process.send_after(self(), :tick, Loop.wait(world.loop, Loop.now()))
    {:noreply, world}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, world) do
    case Enum.find(world.players, fn {_id, player} -> player.monitor == monitor end) do
      {id, _player} -> {:noreply, remove(world, id)}
      nil -> {:noreply, world}
    end
  end

  defp stepped(world, due) do
    started = System.monotonic_time(:microsecond)
    world = world |> run(due, Loop.dt(world.loop)) |> broadcast()
    timed(world, System.monotonic_time(:microsecond) - started, due)
  end

  defp timed(world, elapsed_us, due) do
    timings = Enum.take([{elapsed_us, due > 1} | world.timings], @window)
    %{world | timings: timings}
  end

  defp stats_of(world) do
    durations = world.timings |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    count = length(durations)

    %{
      players: map_size(world.players),
      hz: world.hz,
      steps: world.steps,
      ticks: count,
      tick_us: %{
        mean: if(count == 0, do: 0, else: div(Enum.sum(durations), count)),
        p95:
          if(count == 0, do: 0, else: Enum.at(durations, min(count - 1, div(count * 95, 100)))),
        max: List.last(durations) || 0
      },
      behind: Enum.count(world.timings, &elem(&1, 1))
    }
  end

  defp apply_pending(%{pending: pending} = world) when map_size(pending) == 0, do: world

  defp apply_pending(world) do
    state =
      Enum.reduce(world.pending, world.state, fn {id, input}, state ->
        world.game.handle_input(state, id, input)
      end)

    replay =
      Enum.reduce(world.pending, world.replay, fn {id, input}, replay ->
        log(replay, world.steps, {:input, id, input})
      end)

    %{world | state: state, pending: %{}, replay: replay}
  end

  defp run(world, due, dt) do
    state = Enum.reduce(1..due//1, world.state, fn _, state -> world.game.step(state, dt) end)
    %{world | state: state, steps: world.steps + due}
  end

  defp paced(player, false, _world), do: Map.merge(player, %{frames?: false, every: nil, next: 0})
  defp paced(player, true, _world), do: Map.merge(player, %{frames?: true, every: 1, next: 0})

  defp paced(player, rate, world) when is_number(rate) and rate > 0,
    do: Map.merge(player, %{frames?: true, every: max(1, round(world.hz / rate)), next: 0})

  defp broadcast(world) do
    {events, state} = world.game.drain_events(world.state)

    players =
      Map.new(world.players, fn {id, player} -> {id, framed(world, state, id, player, events)} end)

    Events.broadcast(self(), world.steps, events)
    %{world | state: state, players: players}
  end

  defp framed(_world, _state, _id, %{frames?: false} = player, _events), do: player

  defp framed(world, _state, _id, %{next: next} = player, events) when world.steps < next,
    do: %{player | events: player.events ++ events}

  defp framed(world, state, id, player, events) do
    frame = %{
      tick: world.steps,
      view: world.game.view(state, id),
      events: player.events ++ events
    }

    send(player.pid, {:cauldron_frame, frame})
    %{player | events: [], next: world.steps + player.every}
  end

  defp remove(world, id) do
    case Map.pop(world.players, id) do
      {nil, _players} ->
        world

      {%{monitor: monitor}, players} ->
        Process.demonitor(monitor, [:flush])
        Presence.broadcast(self(), :left, id)

        %{
          world
          | state: world.game.leave(world.state, id),
            players: players,
            pending: Map.delete(world.pending, id)
        }
        |> record({:leave, id})
    end
  end

  defp record(world, action), do: %{world | replay: log(world.replay, world.steps, action)}

  defp log(nil, _tick, _action), do: nil
  defp log(replay, tick, action), do: Replay.record(replay, tick, action)

  defp stamped(nil, _steps), do: nil
  defp stamped(replay, steps), do: Replay.stepped(replay, steps)
end
