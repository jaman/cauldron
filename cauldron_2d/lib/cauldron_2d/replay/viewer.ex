defmodule Cauldron2D.Replay.Viewer do
  @moduledoc """
  Plays a `Cauldron2D.Replay` back on a clock, sending a watcher the frames one
  recorded player saw.

      {:ok, viewer} = Cauldron2D.Replay.Viewer.start_link(replay: replay, game: MyGame, game_opts: [seed: 7], hz: 50, as: "alice", watcher: self())

  The watcher receives `{:cauldron_frame, %{tick: n, view: view, events: events}}` for
  every tick after the player `:as` has joined, exactly as a `Cauldron2D.World` sends
  them, and `{:cauldron_replay, viewer, :done, state}` with the final state when the
  record runs out; the viewer then stops. `pause/1`, `resume/1` and `step/1` drive it.

  ## Options

    * `:replay`, `:game` — the record and the game it was made with. Required
    * `:game_opts` — the game's options, as recorded. Default `[]`
    * `:hz` — the rate the world ran at, so the `dt` of a step. Default `50`
    * `:speed` — how many times faster than that to play. Default `1`
    * `:as` — the recorded player whose view is sent. Required
    * `:watcher` — the process the frames go to. Default the caller
    * `:paused?` — start paused. Default `false`
  """

  use GenServer

  alias Cauldron2D.Replay

  @doc "Start a viewer; see the module documentation for the options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, Keyword.put_new(opts, :watcher, self()))

  @doc "Stop the clock."
  @spec pause(GenServer.server()) :: :ok
  def pause(viewer), do: GenServer.call(viewer, :pause)

  @doc "Start the clock again."
  @spec resume(GenServer.server()) :: :ok
  def resume(viewer), do: GenServer.call(viewer, :resume)

  @doc "Run one tick while paused."
  @spec step(GenServer.server()) :: :ok
  def step(viewer), do: GenServer.call(viewer, :step)

  @impl GenServer
  def init(opts) do
    replay = Keyword.fetch!(opts, :replay)
    game = Keyword.fetch!(opts, :game)
    hz = Keyword.get(opts, :hz, 50)

    state = %{
      game: game,
      state: game.init(Keyword.get(opts, :game_opts, [])),
      by_tick: replay |> Replay.entries() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)),
      steps: replay.steps,
      tick: 0,
      dt: 1 / hz,
      interval: max(1, round(1000 / (hz * Keyword.get(opts, :speed, 1)))),
      as: Keyword.fetch!(opts, :as),
      watcher: Keyword.fetch!(opts, :watcher),
      paused?: Keyword.get(opts, :paused?, false),
      joined: MapSet.new()
    }

    unless state.paused?, do: Process.send_after(self(), :tick, state.interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:pause, _from, state), do: {:reply, :ok, %{state | paused?: true}}

  def handle_call(:resume, _from, %{paused?: true} = state) do
    Process.send_after(self(), :tick, state.interval)
    {:reply, :ok, %{state | paused?: false}}
  end

  def handle_call(:resume, _from, state), do: {:reply, :ok, state}

  def handle_call(:step, _from, state) do
    case advance(state) do
      {:done, state} -> {:stop, :normal, :ok, state}
      {:more, state} -> {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_info(:tick, %{paused?: true} = state), do: {:noreply, state}

  def handle_info(:tick, state) do
    case advance(state) do
      {:done, state} ->
        {:stop, :normal, state}

      {:more, state} ->
        Process.send_after(self(), :tick, state.interval)
        {:noreply, state}
    end
  end

  defp advance(%{tick: tick, steps: steps} = state) when tick >= steps do
    state = apply_tick(state, tick)
    send(state.watcher, {:cauldron_replay, self(), :done, state.state})
    {:done, state}
  end

  defp advance(state) do
    state = apply_tick(state, state.tick)
    {events, game_state} = state.state |> state.game.step(state.dt) |> state.game.drain_events()
    state = %{state | state: game_state, tick: state.tick + 1}

    if MapSet.member?(state.joined, state.as) do
      send(
        state.watcher,
        {:cauldron_frame,
         %{tick: state.tick, view: state.game.view(game_state, state.as), events: events}}
      )
    end

    {:more, state}
  end

  defp apply_tick(state, tick) do
    state.by_tick
    |> Map.get(tick, [])
    |> Enum.reduce(state, fn action, acc -> apply_action(acc, action) end)
  end

  defp apply_action(state, {:join, id, props}) do
    case state.game.join(state.state, id, props) do
      {:ok, joined} -> %{state | state: joined, joined: MapSet.put(state.joined, id)}
      {:error, _reason} -> state
    end
  end

  defp apply_action(state, {:leave, id}),
    do: %{
      state
      | state: state.game.leave(state.state, id),
        joined: MapSet.delete(state.joined, id)
    }

  defp apply_action(state, {:input, id, input}),
    do: %{state | state: state.game.handle_input(state.state, id, input)}
end
