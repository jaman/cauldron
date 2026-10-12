defmodule Cauldron2D.World.Lockstep do
  @moduledoc """
  How a `Cauldron2D.World` on one machine keeps a world on another in step with it.

  The host keeps each join, leave and input it applies, in order (`logged/2`), and after
  each tick sends every follower `{:cauldron_steps, host, base, actions, due, check}`
  (`flushed/3`): the actions it applied since the last, the steps it then ran (`due`)
  from step `base`, and every #{60} steps `{step, checksum}` of the state the steps left
  (`Cauldron2D.Game.checksum/1`). A follower applies the same actions to its own state
  and runs the same steps (`followed/2`), draining the game's events after each and
  keeping them in `drained` for its next frames. A player of the follower's own is
  `ready` once its join comes back from the host, and is sent frames from then on. One that finds itself at another step than
  `base`, or whose checksum differs, takes the host's state again (`resynced/1`).

  A follower starts from `start/1` of the host: the game's `Cauldron2D.Game.export/1` of
  the state, the step and the tick rate. Its state is `Cauldron2D.Game.restore/1` of it.
  """

  alias Cauldron2D.Loop

  @check_every 60

  @type start :: %{state: term(), steps: non_neg_integer(), hz: number()}
  @type action :: {:join, term(), map()} | {:leave, term()} | {:input, term(), term()}

  @doc "`world` keeping `action` for its followers; nothing kept while it has none."
  @spec logged(map(), action()) :: map()
  def logged(%{followers: followers} = world, _action) when map_size(followers) == 0, do: world
  def logged(world, action), do: %{world | applied: [action | world.applied]}

  @doc """
  `world` after sending its followers what it applied and the `due` steps it ran from
  step `base`, with `check/3` as the steps left the state.
  """
  @spec flushed(map(), non_neg_integer(), non_neg_integer(), tuple() | nil) :: map()
  def flushed(%{applied: []} = world, _base, 0, _check), do: world

  def flushed(%{followers: followers} = world, _base, _due, _check) when map_size(followers) == 0,
    do: world

  def flushed(world, base, due, check) do
    message = {:cauldron_steps, self(), base, Enum.reverse(world.applied), due, check}
    Enum.each(Map.keys(world.followers), &send(&1, message))
    %{world | applied: []}
  end

  @doc "`{step, checksum}` of the state when `due` steps from `base` passed a checking step, else `nil`; `nil` while `world` has no followers."
  @spec check(map(), non_neg_integer(), non_neg_integer()) :: {non_neg_integer(), term()} | nil
  def check(%{followers: followers}, _base, _due) when map_size(followers) == 0, do: nil

  def check(world, base, due) do
    after_steps = base + due

    if due > 0 and div(after_steps, @check_every) > div(base, @check_every),
      do: {after_steps, checksum(world.game, world.state)}
  end

  @doc "What a follower of `world` starts from, once what `world` applied is sent to those following it already."
  @spec start(map()) :: {map(), start()}
  def start(world) do
    world = flushed(world, world.steps, 0, nil)
    {world, %{state: export(world.game, world.state), steps: world.steps, hz: world.hz}}
  end

  @doc "`world`, a follower, at the step and state of `start`."
  @spec started(map(), start()) :: map()
  def started(world, %{state: exported, steps: steps}),
    do: %{world | state: restored(world.game, exported), steps: steps}

  @doc """
  `world`, a follower, after the host's `{base, actions, due, check}` and every further
  one already waiting in its mailbox. Returns `{world, stepped?}`.
  """
  @spec followed(map(), tuple()) :: {map(), boolean()}
  def followed(world, steps) do
    {world, stepped?} = applied(world, steps)
    more(world, stepped?)
  end

  defp more(%{host: %{pid: host}} = world, stepped?) do
    receive do
      {:cauldron_steps, ^host, base, actions, due, check} ->
        {world, now?} = applied(world, {base, actions, due, check})
        more(world, stepped? or now?)
    after
      0 -> {world, stepped?}
    end
  end

  defp applied(%{steps: steps} = world, {base, _actions, _due, _check}) when base < steps,
    do: {world, false}

  defp applied(%{steps: steps} = world, {base, _actions, _due, _check}) when base > steps,
    do: {resynced(world), true}

  defp applied(world, {_base, actions, due, check}) do
    world = Enum.reduce(actions, world, &ready/2)
    state = Enum.reduce(actions, world.state, &act(world.game, &2, &1))

    state =
      Enum.reduce(1..due//1, state, fn _step, state ->
        world.game.step(state, Loop.dt(world.loop))
      end)

    world = agreed(%{world | state: state, steps: world.steps + due}, check)
    {events, state} = world.game.drain_events(world.state)
    {%{world | state: state, drained: world.drained ++ events}, due > 0}
  end

  defp ready({:join, id, _props}, world) when is_map_key(world.players, id),
    do: put_in(world.players[id].ready, true)

  defp ready(_action, world), do: world

  defp act(game, state, {:join, id, props}) do
    case game.join(state, id, props) do
      {:ok, joined} -> joined
      {:error, _reason} -> state
    end
  end

  defp act(game, state, {:leave, id}), do: game.leave(state, id)
  defp act(game, state, {:input, id, input}), do: game.handle_input(state, id, input)

  defp agreed(world, nil), do: world

  defp agreed(world, {step, sum}) do
    if step == world.steps and checksum(world.game, world.state) != sum,
      do: resynced(world),
      else: world
  end

  @doc "`world`, a follower, at the host's state and step as they are now."
  @spec resynced(map()) :: map()
  def resynced(%{host: %{pid: host}} = world),
    do: started(world, GenServer.call(host, {:follow_again, self()}))

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
