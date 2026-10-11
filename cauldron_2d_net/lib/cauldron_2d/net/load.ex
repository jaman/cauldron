defmodule Cauldron2D.Net.Load do
  @moduledoc """
  A load test against a running server: players and watchers joining its worlds over
  the wire, the frames they get measured against the steps the server runs, and the
  server's own numbers (`Cauldron2D.Net.Api`'s `/stats`) alongside.

      Cauldron2D.Net.Load.run(url: "http://arcade:2280/api", actions: ["left", "right", "fire"], players: 40, watchers: 100, seconds: 60)
      Cauldron2D.Net.Load.run(url: "http://arcade:2280/api", actions: [], players: 10, ramp: 10, every: 5, seconds: 120)

  Sessions are accounts `load_1`, `load_2`… (password `load test`), registered on the
  server if they are not there, and spread over the worlds in turn. A report goes out
  every `:every` seconds: a line with the sessions joined, the frames a second they
  got (mean and least) against the ticks a second the server's worlds are set to, the
  longest gap between frames, and the node (how busy its schedulers were since the
  last report, the run queue, processes, memory); then a line for each of the three
  worlds with the longest ticks — the mean, the 95th percentile and the longest against
  the tick's budget, and the share of the last ticks that ran more than one step
  (`behind`; a little is timer jitter, more is a world that cannot keep up).

  A run is **degraded** when, over one report, any world's 95th-percentile tick is
  longer than its budget (`1 / hz`), any world ran behind on more than a fifth of its
  ticks (a few double steps are the timer firing late on a busy node, not a world that
  cannot keep up — its ticks say which), the least frame rate any session saw fell
  under 80% of the tick rate, or a session waited over a second for a frame. The
  report says so and why. With
  `:ramp`, that many more sessions join at every report until the run is degraded —
  the sessions before the last addition are the `capacity` in the summary — or the
  time is up.

  `stop/0` from another process ends a run early, after the interval in progress,
  with the summary of what was measured; a mix task can call it on a key press.

  ## Options

    * `:url` — the server's API, default `http://localhost:2280/api`
    * `:actions` — the action names a player holds at random. Required
    * `:topic` — the channel's topic prefix, default `"world"`
    * `:players`, `:watchers` — how many of each to start with, default 10 and 0
    * `:worlds` — the ids of the worlds to use, default every world the server lists
    * `:seconds` — how long the run lasts, default 30
    * `:every` — seconds between reports (and ramp steps), default 5
    * `:ramp` — sessions to add at every report, default none; they are players and
      watchers in the same proportion as the start
    * `:audio` — `:personal` (default) for a session that takes the server's sound as a
      browser would, `:off` for one that asks for none
    * `:password` — the sessions' password, default `load test`
    * `:report` — a function given each report, default `IO.puts/1`
    * `:out` — a file every report and the summary are appended to as JSON, one
      object a line, as the run goes, so a run cut short still leaves its record.
      Default none

  Returns the summary: `sessions`, `joined`, `refused`, `refusals` (reasons with their
  counts), `fps` (`mean`, `min` over the whole run), `gap_ms` (`max`), `join_ms`
  (`mean`, `max`), `server` (the last `worlds` and `node` stats, `hz` and
  `steps_per_second`), `degraded` (`%{sessions, why}` for the first degraded report,
  else `nil`), `capacity` and `stopped` (`:time`, `:degraded` or `:asked`).
  """

  alias Cauldron2D.Net.Load.Session
  alias Cauldron2D.Net.Remote

  @type summary :: %{
          sessions: non_neg_integer(),
          joined: non_neg_integer(),
          refused: non_neg_integer(),
          refusals: %{term() => pos_integer()},
          fps: %{mean: float(), min: float()},
          gap_ms: %{max: non_neg_integer()},
          join_ms: %{mean: non_neg_integer(), max: non_neg_integer()},
          server: %{worlds: [map()], node: map(), hz: number(), steps_per_second: float()},
          degraded: %{sessions: non_neg_integer(), why: [String.t()]} | nil,
          capacity: non_neg_integer() | nil,
          stopped: :time | :degraded | :asked
        }

  @slowdown 0.8
  @stall_ms 1000
  @behind 0.2

  @doc "End the run in progress after the interval it is measuring; nothing when none is running."
  @spec stop() :: :ok
  def stop do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      runner ->
        send(runner, :stop)
        :ok
    end
  end

  @doc "Run a load test; see the module documentation for the options and the summary."
  @spec run(keyword()) :: summary()
  def run(opts) do
    url = Keyword.get(opts, :url, "http://localhost:2280/api")
    report = Keyword.get(opts, :report, &IO.puts/1)
    {:ok, listed} = Remote.worlds(url)
    worlds = Keyword.get(opts, :worlds) || Enum.map(listed, & &1.id)
    if worlds == [], do: raise(ArgumentError, "the server at #{url} lists no worlds")

    Process.register(self(), __MODULE__)

    run = %{
      url: url,
      worlds: worlds,
      actions: Keyword.fetch!(opts, :actions),
      topic: Keyword.get(opts, :topic, "world"),
      password: Keyword.get(opts, :password, "load test"),
      players: Keyword.get(opts, :players, 10),
      watchers: Keyword.get(opts, :watchers, 0),
      ramp: Keyword.get(opts, :ramp),
      every: Keyword.get(opts, :every, 5),
      seconds: Keyword.get(opts, :seconds, 30),
      audio: Keyword.get(opts, :audio, :personal),
      report: report,
      out: Keyword.get(opts, :out),
      sessions: [],
      steps: server_steps(url),
      started: System.monotonic_time(:millisecond),
      degraded: nil,
      capacity: nil,
      stopped: :time,
      gap: 0,
      intervals: []
    }

    run = start_sessions(run, kinds(run.players, run.watchers))
    run = loop(run)
    summary = summarise(run)
    record(run, %{summary: summary})
    for {session, _kind, _number} <- run.sessions, is_pid(session), do: Session.stop(session)
    Process.unregister(__MODULE__)
    summary
  end

  defp kinds(players, watchers),
    do: List.duplicate(:player, players) ++ List.duplicate(:watcher, watchers)

  defp start_sessions(run, kinds) do
    first = length(run.sessions) + 1

    started =
      kinds
      |> Enum.with_index(first)
      |> Enum.map(fn {kind, number} ->
        Process.sleep(10)
        {start_session(run, number, kind), kind, number}
      end)

    %{run | sessions: run.sessions ++ started}
  end

  defp start_session(run, number, kind) do
    name = "load_#{number}"
    world = Enum.at(run.worlds, rem(number - 1, length(run.worlds)))

    with {:ok, token} <- token(run.url, name, run.password),
         {:ok, session} <-
           Session.start_link(
             url: base(run.url),
             token: token,
             world: world,
             kind: kind,
             actions: run.actions,
             topic: run.topic,
             audio: run.audio
           ) do
      session
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp base(url), do: url |> String.replace_suffix("/api", "") |> String.trim_trailing("/")

  defp token(url, name, password) do
    case Remote.login(url, name, password, true) do
      {:ok, token} -> {:ok, token}
      {:error, _taken} -> Remote.login(url, name, password, false)
    end
  end

  defp loop(run) do
    asked? =
      receive do
        :stop -> true
      after
        run.every * 1000 -> false
      end

    interval = measure(run)
    why = degraded(interval)

    run = %{
      run
      | steps: interval.steps,
        intervals: [interval | run.intervals],
        gap: max(run.gap, interval.gap_ms),
        degraded: run.degraded || if(why != [], do: %{sessions: interval.sessions, why: why})
    }

    run.report.(lines(interval, why))
    record(run, %{interval: interval, degraded: why})
    elapsed = (System.monotonic_time(:millisecond) - run.started) / 1000

    cond do
      asked? ->
        %{run | stopped: :asked}

      elapsed >= run.seconds ->
        run

      run.ramp == nil ->
        loop(run)

      why != [] ->
        %{run | capacity: max(interval.sessions - run.ramp, 0), stopped: :degraded}

      true ->
        run |> start_sessions(ramp_kinds(run)) |> loop()
    end
  end

  @doc "Why an interval counts as degraded, as `run/1` judges it: `[]` when it does not."
  @spec degraded(map()) :: [String.t()]
  def degraded(interval) do
    budget = if interval.hz > 0, do: 1_000_000 / interval.hz, else: nil

    over_budget =
      for world <- interval.worlds,
          budget != nil,
          world.tick_us.p95 > budget,
          do:
            "#{world.name}'s ticks run #{ms(world.tick_us.p95)} at the 95th percentile, over the #{ms(budget)} budget"

    behind =
      for world <- interval.worlds,
          world.ticks > 0,
          world.behind / world.ticks > @behind,
          do:
            "#{world.name} ran behind on #{round(world.behind / world.ticks * 100)}% of its ticks"

    slow =
      if interval.fps.min < @slowdown * interval.hz,
        do: [
          "a session got #{Float.round(interval.fps.min, 1)} frames a second of #{interval.hz}"
        ],
        else: []

    stalled =
      if interval.gap_ms > @stall_ms,
        do: ["a session waited #{interval.gap_ms} ms for a frame"],
        else: []

    over_budget ++ behind ++ slow ++ stalled
  end

  defp ms(us), do: "#{Float.round(us / 1000, 1)} ms"

  defp record(%{out: nil}, _entry), do: :ok

  defp record(%{out: path}, entry) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(entry) <> "\n", [:append])
  end

  defp ramp_kinds(%{ramp: ramp, players: players, watchers: watchers}) do
    player_share = if players + watchers == 0, do: 1.0, else: players / (players + watchers)
    player_count = round(ramp * player_share)
    kinds(player_count, ramp - player_count)
  end

  defp measure(run) do
    reports =
      for {session, _kind, _number} <- run.sessions, is_pid(session), do: Session.report(session)

    live = Enum.filter(reports, & &1.joined)
    rates = Enum.map(live, &(&1.recent / run.every))
    steps = server_steps(run.url)
    stats = server_stats(run.url)

    %{
      sessions: length(run.sessions),
      joined: length(live),
      refused:
        Enum.count(reports, &(&1.joined == false)) +
          Enum.count(run.sessions, &(not is_pid(elem(&1, 0)))),
      fps: %{mean: mean(rates), min: Enum.min(rates, fn -> 0.0 end) / 1},
      gap_ms: Enum.map(live, & &1.gap_ms) |> Enum.max(fn -> 0 end),
      steps: steps,
      hz: stats.worlds |> Enum.map(& &1.hz) |> Enum.max(fn -> 0 end),
      steps_per_second: (steps - run.steps) / run.every,
      worlds: stats.worlds,
      node: stats.node
    }
  end

  defp lines(interval, why) do
    busiest = interval.worlds |> Enum.sort_by(& &1.tick_us.p95, :desc) |> Enum.take(3)
    others = length(interval.worlds) - length(busiest)
    budget = if interval.hz > 0, do: 1_000_000 / interval.hz, else: 0
    node = interval.node

    head =
      "sessions #{interval.joined}/#{interval.sessions}  fps #{Float.round(interval.fps.mean, 1)} (min #{Float.round(interval.fps.min, 1)}) of #{interval.hz}  gap #{interval.gap_ms} ms  node #{round(Map.get(node, :busy, 0.0) * 100)}% busy, rq #{Map.get(node, :run_queue, 0)}, #{Map.get(node, :processes, 0)} procs, #{Map.get(node, :memory_mb, 0)} MB"

    worlds =
      for world <- busiest do
        share = if world.ticks > 0, do: round(world.behind / world.ticks * 100), else: 0

        "  #{String.pad_trailing(world.name, 14)} #{String.pad_leading(Integer.to_string(world.players), 3)} in  tick #{ms(world.tick_us.mean)}, p95 #{ms(world.tick_us.p95)}, max #{ms(world.tick_us.max)} of #{ms(budget)}  behind #{share}%"
      end

    more = if others > 0, do: ["  … and #{others} more"], else: []
    verdict = if why == [], do: [], else: ["  DEGRADED: " <> Enum.join(why, "; ")]
    Enum.join([head | worlds ++ more ++ verdict], "\n")
  end

  defp summarise(run) do
    reports =
      for {session, _kind, _number} <- run.sessions, is_pid(session), do: Session.report(session)

    live = Enum.filter(reports, & &1.joined)
    rates = Enum.map(live, &(&1.frames / max(&1.alive_ms, 1) * 1000))
    joins = Enum.map(live, & &1.join_ms)
    last = List.first(run.intervals) || %{worlds: [], node: %{}, hz: 0, steps_per_second: 0.0}

    failed =
      for {session, _kind, _number} <- run.sessions, not is_pid(session), do: elem(session, 1)

    refusals =
      (Enum.map(reports, &(&1.joined == false && &1.reason)) ++ failed)
      |> Enum.reject(&(&1 == false))
      |> Enum.frequencies()

    %{
      sessions: length(run.sessions),
      joined: length(live),
      refused: length(run.sessions) - length(live),
      refusals: refusals,
      fps: %{mean: mean(rates), min: Enum.min(rates, fn -> 0.0 end) / 1},
      gap_ms: %{max: max(run.gap, Enum.map(live, & &1.gap_ms) |> Enum.max(fn -> 0 end))},
      join_ms: %{mean: round(mean(joins)), max: Enum.max(joins, fn -> 0 end)},
      server: %{
        worlds: last.worlds,
        node: last.node,
        hz: last.hz,
        steps_per_second: last.steps_per_second
      },
      degraded: run.degraded,
      capacity: run.capacity,
      stopped: run.stopped
    }
  end

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / length(values)

  defp server_steps(url),
    do: url |> server_stats() |> Map.get(:worlds) |> Enum.map(& &1.steps) |> Enum.max(fn -> 0 end)

  defp server_stats(url) do
    case Remote.stats(url) do
      {:ok, stats} ->
        stats

      {:error, _reason} ->
        %{worlds: [], node: %{processes: 0, memory_mb: 0, run_queue: 0, schedulers: 0, busy: 0.0}}
    end
  end
end
