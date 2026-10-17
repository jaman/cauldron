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
    * `:follow` — another world, on this machine or another, to follow instead of
      running one of its own, or `{:link, address, port}`: the world behind a
      `Cauldron2D.Link` listener there, which the world connects to itself and plays
      with rollback, closing the connection when it stops. Default none
    * `:rollback` — with `:follow`, play the host's game with rollback
      (`Cauldron2D.World.Rollback`) instead of following it step by step: a keyword
      list of `:delay`, `:window` and `:lead`, or `true` for their defaults. Default none
    * `:join_props` — with `:follow`, props added to every join of this world's players
      sent to the host. Default none

  ## Following

  A world started with `follow: host` runs the host's game on its own copy of the host's
  state (`Cauldron2D.World.Lockstep`): it has no clock, and after each of the host's
  ticks applies the joins, leaves and input the host applied and runs the steps the host
  ran, then sends its own players their frames. Its players' joins, leaves and input go
  to the host, which takes them into its next tick as its own players', so only those
  cross between the machines, never views. `pause/1` and `resume/1` do nothing on a
  follower and `paused?/1` is `false`: only the host's own players pause the game. A
  follower stops, with reason `:normal`, when the host does. Starting one fails with
  `{:error, {:host, reason}}` when the host cannot be reached within `:timeout`
  milliseconds (default `10_000`).

  ## Rollback

  A world started with `follow: host, rollback: opts` runs the host's game on its own
  clock instead, from the host's state when it starts. Both worlds apply their own
  players' input as soon as it comes, a few frames ahead, and run the other's input
  again when it arrives late (`Cauldron2D.World.Rollback`). The host decides every join
  and leave. A host plays with rollback against one world at a time, and a world playing
  with rollback has no followers. When the host stops, the other world stops with reason
  `:normal`; when the other world stops, the host goes on alone. The other world adds
  `round_trip`, its round trip to the host in milliseconds when it started, to the props
  of every join of its players it sends the host.
  """

  use GenServer

  alias Cauldron2D.{Link, Loop, Replay}
  alias Cauldron2D.World.{Events, Lockstep, Presence, Rollback}

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
  @host_call_ms 9_000

  @doc "Start a world not linked to the caller, as `start_link/1` does otherwise."
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start(__MODULE__, opts, gen_opts)
  end

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
    case {Keyword.get(opts, :follow), Keyword.get(opts, :rollback)} do
      {nil, _rollback} -> {:ok, hosting(opts)}
      {{:link, address, port}, rollback} -> linked(opts, address, port, rollback || true)
      {host, nil} -> following(opts, host)
      {host, rollback} -> rolling(opts, host, rollback_opts(rollback))
    end
  end

  @impl GenServer
  def terminate(_reason, %{link: link}) when is_pid(link) do
    if Process.alive?(link), do: Link.close(link)
    :ok
  end

  def terminate(_reason, _world), do: :ok

  defp linked(opts, address, port, rollback) do
    case Link.connect(address, port, Keyword.get(opts, :timeout, 10_000)) do
      {:ok, link} -> rolled_over(link, rolling(opts, link, rollback_opts(rollback)))
      {:error, reason} -> {:stop, {:host, reason}}
    end
  end

  defp rolled_over(link, {:ok, world}), do: {:ok, %{world | link: link}}

  defp rolled_over(link, {:stop, reason}) do
    Link.close(link)
    {:stop, reason}
  end

  defp round_trip(host, timeout) do
    times =
      for _ping <- 1..5 do
        started = System.monotonic_time(:microsecond)
        GenServer.call(host, :hz, timeout)
        (System.monotonic_time(:microsecond) - started) / 1000
      end

    times |> Enum.sort() |> Enum.at(2)
  end

  defp rollback_opts(true), do: []
  defp rollback_opts(opts) when is_list(opts), do: opts

  defp rolling(opts, host, rollback_opts) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    hz = GenServer.call(host, :hz, timeout)
    round_trip = round_trip(host, timeout)
    delay = Rollback.delay(round_trip, hz)
    rollback_opts = Keyword.put_new(rollback_opts, :delay, delay)

    case GenServer.call(host, {:rollback, self(), rollback_opts}, timeout) do
      {host_pid, %{hz: hz, start: start}} when is_pid(host_pid) ->
        with {:ok, world} <- rolled(opts, host_pid, hz, start, rollback_opts),
             do:
               {:ok,
                %{world | round_trip: round_trip, join_props: Keyword.get(opts, :join_props, %{})}}

      {:error, reason} ->
        {:stop, {:host, reason}}
    end
  catch
    :exit, reason -> {:stop, {:host, reason}}
  end

  defp rolled(opts, host_pid, hz, start, rollback_opts) do
    world = world(Keyword.fetch!(opts, :game), nil, hz, :fixed, false)
    rollback = %{Rollback.new(host_pid, false, rollback_opts) | frames: start.frames}
    send(self(), :tick)

    {:ok,
     %{
       world
       | state: Rollback.restored_state(world.game, start.state),
         steps: start.frame,
         host: %{pid: host_pid, monitor: rollback.monitor},
         rollback: rollback
     }}
  end

  defp hosting(opts) do
    game = Keyword.fetch!(opts, :game)
    tick = Keyword.get(opts, :tick, :fixed)
    if tick == :fixed, do: send(self(), :tick)
    state = Keyword.get_lazy(opts, :state, fn -> game.init(Keyword.get(opts, :game_opts, [])) end)
    world(game, state, Keyword.get(opts, :hz, 50), tick, Keyword.get(opts, :record, false))
  end

  defp following(opts, host) do
    {host_pid, start} =
      GenServer.call(host, {:follow, self()}, Keyword.get(opts, :timeout, 10_000))

    world = world(Keyword.fetch!(opts, :game), nil, start.hz, :follow, false)
    host = %{pid: host_pid, monitor: Process.monitor(host_pid)}
    {:ok, Lockstep.started(%{world | host: host}, start)}
  catch
    :exit, reason -> {:stop, {:host, reason}}
  end

  defp world(game, state, hz, tick, record?) do
    %{
      game: game,
      state: state,
      loop: Loop.new(hz),
      hz: hz,
      tick: tick,
      paused?: false,
      players: %{},
      pending: %{},
      steps: 0,
      timings: [],
      replay: if(record?, do: Replay.new()),
      host: nil,
      followers: %{},
      applied: [],
      drained: [],
      rollback: nil,
      link: nil,
      round_trip: nil,
      join_props: %{}
    }
  end

  @impl GenServer
  def handle_call({:rollback, pid, opts}, _from, %{rollback: nil} = world) do
    world = %{world | rollback: Rollback.new(pid, true, opts)}
    {:reply, {self(), %{hz: world.hz, start: Rollback.start(world)}}, world}
  end

  def handle_call({:rollback, _pid, _opts}, _from, world),
    do: {:reply, {:error, :rollback_taken}, world}

  def handle_call(:hz, _from, world), do: {:reply, world.hz, world}

  def handle_call({:join, id, props, pid, frames?}, _from, %{host: %{pid: host}} = world) do
    props = Map.merge(props, world.join_props)
    props = if world.round_trip, do: Map.put(props, :round_trip, world.round_trip), else: props

    case GenServer.call(host, {:join, id, props, pid, false}, @host_call_ms) do
      :ok -> {:reply, :ok, put_in(world.players[id], unready(player(world, id, pid, frames?)))}
      refused -> {:reply, refused, world}
    end
  end

  def handle_call({:leave, id}, _from, %{host: %{pid: host}} = world) do
    :ok = GenServer.call(host, {:leave, id}, @host_call_ms)
    {:reply, :ok, unfollowed(world, id)}
  end

  def handle_call(:pause, _from, %{rollback: %{}} = world), do: {:reply, :ok, world}
  def handle_call(:pause, _from, %{host: %{}} = world), do: {:reply, :ok, world}
  def handle_call(:resume, _from, %{host: %{}} = world), do: {:reply, :ok, world}
  def handle_call(:paused?, _from, %{host: %{}} = world), do: {:reply, false, world}

  def handle_call({:follow, pid}, _from, world) do
    {world, start} = Lockstep.start(world)
    followers = Map.put(world.followers, pid, Process.monitor(pid))
    {:reply, {self(), start}, %{world | followers: followers}}
  end

  def handle_call({:follow_again, _pid}, _from, world) do
    {world, start} = Lockstep.start(world)
    {:reply, start, world}
  end

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

  defp joined(%{rollback: %{}} = world, id, props, pid, frames?) do
    case world.game.join(world.state, id, props) do
      {:ok, _state} ->
        world = put_in(world.players[id], unready(player(world, id, pid, frames?)))
        {:reply, :ok, Rollback.local(world, {:join, id, props})}

      {:error, reason} ->
        {:reply, {:error, reason}, world}
    end
  end

  defp joined(world, id, props, pid, frames?) do
    case world.game.join(world.state, id, props) do
      {:ok, state} ->
        players = Map.put(world.players, id, player(world, id, pid, frames?))

        {:reply, :ok,
         %{world | state: state, players: players}
         |> record({:join, id, props})
         |> Lockstep.logged({:join, id, props})}

      {:error, reason} ->
        {:reply, {:error, reason}, world}
    end
  end

  defp unready(player), do: Map.put(player, :ready, false)

  defp player(world, id, pid, frames?) do
    Presence.broadcast(self(), :joined, id)
    paced(%{pid: pid, monitor: Process.monitor(pid), events: []}, frames?, world)
  end

  @impl GenServer
  def handle_cast({:input, id, input}, %{rollback: %{}} = world) do
    if Map.has_key?(world.players, id),
      do: {:noreply, Rollback.local(world, {:input, id, input})},
      else: {:noreply, world}
  end

  def handle_cast({:input, id, input}, %{host: %{pid: host}} = world) do
    if Map.has_key?(world.players, id), do: GenServer.cast(host, {:input, id, input})
    {:noreply, world}
  end

  def handle_cast({:input, id, input}, world) do
    if Map.has_key?(world.players, id) do
      {:noreply, %{world | pending: Map.put(world.pending, id, input)} |> step_on_input()}
    else
      {:noreply, world}
    end
  end

  defp step_on_input(%{tick: :on_input} = world) do
    started = System.monotonic_time(:microsecond)
    base = world.steps
    world = world |> apply_pending() |> run(1, Loop.dt(world.loop))
    check = Lockstep.check(world, base, 1)
    world = world |> broadcast() |> Lockstep.flushed(base, 1, check)
    timed(world, System.monotonic_time(:microsecond) - started, 1)
  end

  defp step_on_input(world), do: world

  @impl GenServer
  def handle_info(:tick, %{paused?: true} = world) do
    {_due, loop} = Loop.advance(world.loop, Loop.now())
    Process.send_after(self(), :tick, max(1, round(Loop.dt(loop) * 1000)))
    {:noreply, %{world | loop: loop}}
  end

  def handle_info(:tick, %{rollback: %{}} = world) do
    {due, loop} = Loop.advance(world.loop, Loop.now())
    Process.send_after(self(), :tick, Loop.wait(loop, Loop.now()))
    alone(rolled(%{world | loop: loop}, due))
  end

  def handle_info(:tick, world) do
    {due, loop} = Loop.advance(world.loop, Loop.now())
    base = world.steps
    world = %{world | loop: loop} |> apply_pending()
    world = if due > 0, do: stepped(world, due), else: Lockstep.flushed(world, base, 0, nil)
    Process.send_after(self(), :tick, Loop.wait(world.loop, Loop.now()))
    {:noreply, world}
  end

  def handle_info(
        {:cauldron_steps, host, base, actions, due, check},
        %{host: %{pid: host}} = world
      ) do
    case Lockstep.followed(world, {base, actions, due, check}) do
      {world, true} -> {:noreply, broadcast(world)}
      {world, false} -> {:noreply, world}
    end
  end

  def handle_info(
        {:cauldron_rollback, peer, actions, through, frame},
        %{rollback: %{peer: peer}} = world
      ),
      do: {:noreply, Rollback.received(world, actions, through, frame)}

  def handle_info({:cauldron_rollback_lead, peer, average}, %{rollback: %{peer: peer}} = world),
    do: {:noreply, Rollback.led(world, average)}

  def handle_info({:cauldron_rollback_lead, _peer, _average}, world), do: {:noreply, world}

  def handle_info(
        {:cauldron_rollback_check, peer, frame, sum},
        %{rollback: %{peer: peer}} = world
      ),
      do: {:noreply, Rollback.checked(world, frame, sum)}

  def handle_info({:cauldron_rollback, _peer, _actions, _through, _frame}, world),
    do: {:noreply, world}

  def handle_info({:cauldron_rollback_check, _peer, _frame, _sum}, world), do: {:noreply, world}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{host: %{monitor: monitor}} = world
      ),
      do: {:stop, :normal, world}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{rollback: %{monitor: monitor, host?: true}} = world
      ),
      do: {:noreply, Rollback.ended(world)}

  def handle_info({:DOWN, _monitor, :process, pid, _reason}, world)
      when is_map_key(world.followers, pid) do
    {:noreply, %{world | followers: Map.delete(world.followers, pid)}}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, world) do
    case Enum.find(world.players, fn {_id, player} -> player.monitor == monitor end) do
      {id, _player} -> {:noreply, gone(world, id)}
      nil -> {:noreply, world}
    end
  end

  defp gone(%{host: %{}} = world, id), do: unfollowed(world, id)
  defp gone(world, id), do: remove(world, id)

  defp unfollowed(world, id) do
    case Map.pop(world.players, id) do
      {nil, _players} ->
        world

      {%{monitor: monitor}, players} ->
        Process.demonitor(monitor, [:flush])
        Presence.broadcast(self(), :left, id)
        %{world | players: players}
    end
  end

  defp rolled(world, due) do
    world = Enum.reduce(1..due//1, world, fn _step, world -> rolled_frame(world) end)
    world = if due > 0, do: broadcast(world), else: world
    world |> delay_asked() |> Rollback.flushed()
  end

  defp delay_asked(%{game: game, state: state, rollback: rollback} = world) do
    with true <- function_exported?(game, :input_delay, 1),
         delay when is_integer(delay) and delay > 0 and delay != rollback.delay <-
           game.input_delay(state) do
      Rollback.delayed(world, delay)
    else
      _same -> world
    end
  end

  defp rolled_frame(world) do
    if Rollback.advance?(world) do
      case Rollback.wait(world) do
        {true, world} -> world
        {false, world} -> drained(Rollback.run(world))
      end
    else
      world
    end
  end

  defp alone(world) do
    cond do
      not Rollback.silent?(world) -> {:noreply, world}
      world.rollback.host? -> {:noreply, Rollback.ended(world)}
      true -> {:stop, :normal, world}
    end
  end

  defp drained(world) do
    {events, state} = world.game.drain_events(world.state)
    %{world | state: state, drained: world.drained ++ events}
  end

  defp stepped(world, due) do
    started = System.monotonic_time(:microsecond)
    base = world.steps
    world = run(world, due, Loop.dt(world.loop))
    check = Lockstep.check(world, base, due)
    world = world |> broadcast() |> Lockstep.flushed(base, due, check)
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

    world =
      Enum.reduce(world.pending, world, &Lockstep.logged(&2, {:input, elem(&1, 0), elem(&1, 1)}))

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
    events = world.drained ++ events
    world = %{world | drained: []}

    players =
      Map.new(world.players, fn {id, player} -> {id, framed(world, state, id, player, events)} end)

    Events.broadcast(self(), world.steps, events)
    %{world | state: state, players: players}
  end

  defp framed(_world, _state, _id, %{frames?: false} = player, _events), do: player
  defp framed(_world, _state, _id, %{ready: false} = player, _events), do: player

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

  defp remove(%{rollback: %{}} = world, id) do
    case Map.pop(world.players, id) do
      {nil, _players} ->
        world

      {%{monitor: monitor}, players} ->
        Process.demonitor(monitor, [:flush])
        Presence.broadcast(self(), :left, id)
        Rollback.local(%{world | players: players}, {:leave, id})
    end
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
        |> Lockstep.logged({:leave, id})
    end
  end

  defp record(world, action), do: %{world | replay: log(world.replay, world.steps, action)}

  defp log(nil, _tick, _action), do: nil
  defp log(replay, tick, action), do: Replay.record(replay, tick, action)

  defp stamped(nil, _steps), do: nil
  defp stamped(replay, steps), do: Replay.stepped(replay, steps)
end
