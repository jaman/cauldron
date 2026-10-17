defmodule Cauldron2D.World.Rollback do
  @moduledoc """
  How two `Cauldron2D.World`s, one on each machine, play one game with rollback: each
  runs the game on its own clock, applies its own players' input at once, and runs
  frames again when the other's input arrives late.

  Every join, leave and input is an action stamped with the frame it applies before.
  A world stamps its own players' input `delay` frames ahead of the frame it is on, and
  sends it to its peer once. The host also stamps every join and leave, its own and those
  the other world asks for. Each message also says up to which frame the sender has sent
  every action of its own (`through`) and which frame it is on.

  A frame is run with the actions known for it. A player whose input for a frame is not
  yet known keeps their last input, so held buttons stay held and none is pressed or let
  go. When an action arrives for a frame already run, the world loads the state it kept
  from before that frame and runs the frames again. The game's events from frames run
  again are dropped. A world runs no further than `window` frames past its peer's
  `through` (`advance?/1`).

  Each world measures how far ahead of its peer it runs: its frame less the peer's last
  reported frame, once for every frame it sends. Every 250 milliseconds it averages those
  and sends the average. When its own average less the peer's is 1.5 frames or more, it
  owes 0.3 of that many waits, at most `window`, and skips one step in every three until
  it has waited them (`wait/1`). The world behind never hurries.

  Each world sends the checksum (`Cauldron2D.Game.checksum/1`) of the state before every
  60th frame once both worlds have confirmed it. A checksum that differs is counted in
  `desyncs` and nothing else is done.

  `delay/2` picks the delay from the round trip between the two worlds, and `delayed/2`
  changes it while the worlds play: input stamped further ahead leaves frames with no
  action, which keep the last input, and input stamped nearer comes after the actions
  already sent for its frame, in the same order on both worlds.
  """

  alias Cauldron2D.Loop

  @check_every 60
  @balance_ms 250
  @wait_threshold 1.5
  @wait_share 0.3
  @gap 3
  @timeout_ms 7_000
  @min_delay 2
  @max_delay 3
  @margin_ms 8

  @type action :: {:join, term(), map()} | {:leave, term()} | {:input, term(), term()}

  @type t :: %{
          peer: pid(),
          monitor: reference(),
          host?: boolean(),
          delay: non_neg_integer(),
          window: pos_integer(),
          frames: %{non_neg_integer() => [action()]},
          states: %{non_neg_integer() => term()},
          through: non_neg_integer(),
          sent: [{non_neg_integer(), action()}],
          heard_at: integer(),
          peer_frame: non_neg_integer() | nil,
          samples: [integer()],
          next_average_at: integer(),
          own_average: number() | nil,
          peer_average: number() | nil,
          to_wait: number(),
          gap: non_neg_integer(),
          sums: %{non_neg_integer() => term()},
          peer_sums: %{non_neg_integer() => term()},
          summed: integer(),
          desyncs: non_neg_integer(),
          rollbacks: non_neg_integer(),
          rolled_frames: non_neg_integer()
        }

  @doc """
  The rollback part of a world playing against `peer`. `host?` says whether this world
  stamps joins and leaves. Options: `:delay` (frames, default 2) and `:window` (frames,
  default 7).
  """
  @spec new(pid(), boolean(), keyword()) :: t()
  def new(peer, host?, opts) do
    now = now()

    %{
      peer: peer,
      monitor: Process.monitor(peer),
      host?: host?,
      delay: Keyword.get(opts, :delay, @min_delay),
      window: Keyword.get(opts, :window, 7),
      frames: %{},
      states: %{},
      through: 0,
      sent: [],
      heard_at: now,
      peer_frame: nil,
      samples: [],
      next_average_at: now + @balance_ms,
      own_average: nil,
      peer_average: nil,
      to_wait: 0,
      gap: 0,
      sums: %{},
      peer_sums: %{},
      summed: -1,
      desyncs: 0,
      rollbacks: 0,
      rolled_frames: 0
    }
  end

  @doc """
  The delay in frames for a round trip of `round_trip_ms` between the two worlds at
  `hz` frames a second: half the round trip and 8 milliseconds, in whole frames, from 2
  to 3.
  """
  @spec delay(number(), number()) :: pos_integer()
  def delay(round_trip_ms, hz) do
    frames = ceil((round_trip_ms / 2 + @margin_ms) / (1000 / hz))
    frames |> max(@min_delay) |> min(@max_delay)
  end

  @doc "`world` with its own players' input stamped `delay` frames ahead from now on."
  @spec delayed(map(), pos_integer()) :: map()
  def delayed(%{rollback: rollback} = world, delay),
    do: %{world | rollback: %{rollback | delay: delay}}

  @doc "`world` with `action` by one of its own players stamped and kept to send."
  @spec local(map(), action()) :: map()
  def local(%{rollback: rollback} = world, action) do
    frame = world.steps + rollback.delay
    rollback = %{rollback | sent: [{frame, action} | rollback.sent]}
    %{world | rollback: %{rollback | frames: added(rollback.frames, frame, action)}}
  end

  @doc """
  `world` after sending its peer the actions stamped since the last message, and its
  average lead when one is due.
  """
  @spec flushed(map()) :: map()
  def flushed(%{rollback: rollback} = world) do
    through = world.steps + rollback.delay
    message = {:cauldron_rollback, self(), Enum.reverse(rollback.sent), through, world.steps}
    send(rollback.peer, message)

    samples =
      if rollback.peer_frame,
        do: [world.steps - rollback.peer_frame | rollback.samples],
        else: rollback.samples

    averaged(%{world | rollback: %{rollback | sent: [], samples: samples, peer_frame: nil}})
  end

  defp averaged(%{rollback: rollback} = world) do
    now = now()

    cond do
      now < rollback.next_average_at ->
        world

      rollback.samples == [] ->
        put_in(world.rollback.next_average_at, rollback.next_average_at + @balance_ms)

      true ->
        average = trunc(Enum.sum(rollback.samples) / length(rollback.samples) * 1000) / 1000
        send(rollback.peer, {:cauldron_rollback_lead, self(), average})

        rollback = %{
          rollback
          | next_average_at: rollback.next_average_at + @balance_ms,
            samples: [],
            own_average: average
        }

        balanced(%{world | rollback: rollback})
    end
  end

  @doc "`world` after the peer's average lead."
  @spec led(map(), number()) :: map()
  def led(world, average), do: balanced(put_in(world.rollback.peer_average, average))

  defp balanced(%{rollback: %{own_average: own, peer_average: peer}} = world)
       when is_number(own) and is_number(peer) do
    diff = own - peer
    rollback = %{world.rollback | own_average: nil, peer_average: nil}

    to_wait =
      if diff >= @wait_threshold,
        do: min(rollback.to_wait + diff * @wait_share, max(2, rollback.window)),
        else: 0

    %{world | rollback: %{rollback | to_wait: to_wait}}
  end

  defp balanced(world), do: world

  @doc """
  `world` after the peer's `actions`, `through` and `frame`: the actions kept, and the
  frames already run with an action now known for them run again.
  """
  @spec received(map(), [{non_neg_integer(), action()}], non_neg_integer(), non_neg_integer()) ::
          map()
  def received(%{rollback: rollback} = world, actions, through, frame) do
    frames =
      Enum.reduce(actions, rollback.frames, fn {at, action}, acc -> added(acc, at, action) end)

    rollback = %{
      rollback
      | frames: frames,
        through: max(rollback.through, through),
        heard_at: now(),
        peer_frame: frame
    }

    earliest = actions |> Enum.map(&elem(&1, 0)) |> Enum.min(fn -> nil end)

    %{world | rollback: rollback}
    |> rolled_back(earliest)
    |> trimmed()
  end

  @doc "Whether `world` may run its next frame: no more than `window` frames past what its peer confirmed."
  @spec advance?(map()) :: boolean()
  def advance?(%{rollback: rollback} = world),
    do: world.steps < rollback.through + rollback.window

  @doc """
  Whether `world` skips this step to let its peer catch up, and `world` with the wait
  counted. It skips one step in every three while it owes a wait.
  """
  @spec wait(map()) :: {boolean(), map()}
  def wait(%{rollback: %{to_wait: to_wait}} = world) when to_wait < 1, do: {false, world}

  def wait(%{rollback: rollback} = world) do
    case rollback.gap + 1 do
      @gap -> {true, %{world | rollback: %{rollback | gap: 0, to_wait: rollback.to_wait - 1}}}
      gap -> {false, %{world | rollback: %{rollback | gap: gap}}}
    end
  end

  @doc "Whether `world` has heard nothing from its peer for 7 seconds."
  @spec silent?(map()) :: boolean()
  def silent?(%{rollback: rollback}), do: now() - rollback.heard_at >= @timeout_ms

  @doc """
  `world` after running its next frame: the state kept, the frame's actions applied, one
  step of the game run.
  """
  @spec run(map()) :: map()
  def run(%{rollback: rollback} = world) do
    frame = world.steps
    actions = Map.get(rollback.frames, frame, [])
    states = Map.put(rollback.states, frame, world.state)
    world = Enum.reduce(actions, world, &ready/2)
    state = Enum.reduce(actions, world.state, &act(world.game, &2, &1))
    state = world.game.step(state, Loop.dt(world.loop))
    %{world | state: state, steps: frame + 1, rollback: %{rollback | states: states}}
  end

  defp rolled_back(world, nil), do: world
  defp rolled_back(%{steps: steps} = world, from) when from >= steps, do: world

  defp rolled_back(%{rollback: rollback} = world, from) do
    case Map.fetch(rollback.states, from) do
      {:ok, state} -> replayed(%{world | state: state, steps: from}, world.steps)
      :error -> world
    end
  end

  defp replayed(world, until) do
    count = max(until - world.steps, 0)

    world =
      Enum.reduce(1..count//1, world, fn _frame, world ->
        world = run(world)
        {_events, state} = world.game.drain_events(world.state)
        %{world | state: state}
      end)

    rollback = world.rollback

    %{
      world
      | rollback: %{
          rollback
          | rollbacks: rollback.rollbacks + 1,
            rolled_frames: rollback.rolled_frames + count
        }
    }
  end

  defp trimmed(%{rollback: rollback} = world) do
    keep_from = min(rollback.through, world.steps)

    {dropped, kept} =
      Enum.split_with(rollback.states, fn {frame, _state} -> frame < keep_from end)

    frames = Map.filter(rollback.frames, fn {frame, _actions} -> frame >= keep_from end)
    summed(%{world | rollback: %{rollback | states: Map.new(kept), frames: frames}}, dropped)
  end

  defp summed(world, dropped) do
    due =
      for {frame, state} <- Enum.sort(dropped),
          rem(frame, @check_every) == 0,
          frame > world.rollback.summed,
          do: {frame, state}

    Enum.reduce(due, world, fn {frame, state}, world ->
      sum = checksum(world.game, state)
      send(world.rollback.peer, {:cauldron_rollback_check, self(), frame, sum})
      rollback = world.rollback

      compared(%{
        world
        | rollback: %{rollback | summed: frame, sums: Map.put(rollback.sums, frame, sum)}
      })
    end)
  end

  @doc "`world` after the peer's checksum `sum` of the state before `frame`."
  @spec checked(map(), non_neg_integer(), term()) :: map()
  def checked(%{rollback: rollback} = world, frame, sum),
    do:
      compared(%{
        world
        | rollback: %{rollback | peer_sums: Map.put(rollback.peer_sums, frame, sum)}
      })

  defp compared(%{rollback: rollback} = world) do
    both =
      for {frame, sum} <- rollback.sums, Map.has_key?(rollback.peer_sums, frame), do: {frame, sum}

    differing = Enum.count(both, fn {frame, sum} -> rollback.peer_sums[frame] != sum end)
    frames = Enum.map(both, &elem(&1, 0))

    %{
      world
      | rollback: %{
          rollback
          | sums: Map.drop(rollback.sums, frames),
            peer_sums: Map.drop(rollback.peer_sums, frames),
            desyncs: rollback.desyncs + differing
        }
    }
  end

  @doc """
  What the host sends the other world when it starts: the frame the host is on, its
  state, and every action it holds from that frame on.
  """
  @spec start(map()) :: %{frame: non_neg_integer(), state: term(), frames: map()}
  def start(%{rollback: rollback} = world) do
    frames = Map.filter(rollback.frames, fn {at, _actions} -> at >= world.steps end)
    %{frame: world.steps, state: export(world.game, world.state), frames: frames}
  end

  @doc """
  `world` playing on alone: every action it holds for a frame not yet run applied now,
  in frame order, and its rollback part gone.
  """
  @spec ended(map()) :: map()
  def ended(%{rollback: rollback} = world) do
    state =
      rollback.frames
      |> Enum.filter(fn {frame, _actions} -> frame >= world.steps end)
      |> Enum.sort()
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.reduce(world.state, &act(world.game, &2, &1))

    %{world | state: state, rollback: nil}
  end

  @doc "The game state `exported` stands for, as `Cauldron2D.Game.restore/1` makes it."
  @spec restored_state(module(), term()) :: term()
  def restored_state(game, exported), do: restored(game, exported)

  @doc """
  The world's rollback counts: how many times it went back, how many frames it ran
  again, and how many checksums differed from its peer's.
  """
  @spec stats(map()) :: %{
          rollbacks: non_neg_integer(),
          frames: non_neg_integer(),
          desyncs: non_neg_integer()
        }
  def stats(%{rollback: rollback}),
    do: %{
      rollbacks: rollback.rollbacks,
      frames: rollback.rolled_frames,
      desyncs: rollback.desyncs
    }

  defp added(frames, frame, action), do: Map.update(frames, frame, [action], &(&1 ++ [action]))

  defp ready({:join, id, _props}, world) when is_map_key(world.players, id),
    do: put_in(world.players[id][:ready], true)

  defp ready(_action, world), do: world

  defp act(game, state, {:join, id, props}) do
    case game.join(state, id, props) do
      {:ok, joined} -> joined
      {:error, _reason} -> state
    end
  end

  defp act(game, state, {:leave, id}), do: game.leave(state, id)
  defp act(game, state, {:input, id, input}), do: game.handle_input(state, id, input)

  defp now, do: System.monotonic_time(:millisecond)

  defp export(game, state), do: optional(game, :export, state, fn -> state end)
  defp restored(game, exported), do: optional(game, :restore, exported, fn -> exported end)

  defp checksum(game, state),
    do: optional(game, :checksum, state, fn -> :erlang.phash2(state) end)

  defp optional(game, callback, argument, default) do
    if Code.ensure_loaded?(game) and function_exported?(game, callback, 1),
      do: apply(game, callback, [argument]),
      else: default.()
  end
end
