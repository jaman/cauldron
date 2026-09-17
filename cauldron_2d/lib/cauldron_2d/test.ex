defmodule Cauldron2D.Test do
  @moduledoc """
  Drives a `Cauldron2D.Game` in a test, with no world process and no clock: join
  players, hold actions, run ticks, read views and events.

      driver = Cauldron2D.Test.new(MyGame, game_opts: [seed: 1], hz: 50)
      {:ok, driver} = Cauldron2D.Test.join(driver, :alice, %{username: "alice"})
      driver = driver |> Cauldron2D.Test.hold(:alice, [:thrust]) |> Cauldron2D.Test.tick(10)
      Cauldron2D.Test.view(driver, :alice)
      Cauldron2D.Test.events(driver)

  A tick is what `Cauldron2D.World` does on one step: the input held since the last tick
  is applied, the game steps by `1 / hz`, and its events are drained and kept, oldest
  first. `until/3` ticks until a condition holds or a limit is reached.
  """

  @type t :: %__MODULE__{
          game: module(),
          state: term(),
          dt: float(),
          pending: %{term() => Cauldron2D.Input.state()},
          events: [term()],
          ticks: non_neg_integer()
        }

  @enforce_keys [:game, :state, :dt]
  defstruct [:game, :state, :dt, pending: %{}, events: [], ticks: 0]

  @doc "A driver for `game`; options `:game_opts` (default `[]`) and `:hz` (default `50`)."
  @spec new(module(), keyword()) :: t()
  def new(game, opts \\ []) do
    %__MODULE__{
      game: game,
      state: game.init(Keyword.get(opts, :game_opts, [])),
      dt: 1 / Keyword.get(opts, :hz, 50)
    }
  end

  @doc "Join player `id` with `props`; the game's refusal is returned as it gave it."
  @spec join(t(), term(), map()) :: {:ok, t()} | {:error, term()}
  def join(%__MODULE__{} = driver, id, props) do
    with {:ok, state} <- driver.game.join(driver.state, id, props),
         do: {:ok, %{driver | state: state}}
  end

  @doc "Player `id` leaves."
  @spec leave(t(), term()) :: t()
  def leave(%__MODULE__{} = driver, id),
    do: %{
      driver
      | state: driver.game.leave(driver.state, id),
        pending: Map.delete(driver.pending, id)
    }

  @doc "What player `id` holds from the next tick: a list of actions, an aim, and optionally how hard each action is held."
  @spec hold(t(), term(), [atom()], {number(), number()} | nil, %{atom() => float()}) :: t()
  def hold(%__MODULE__{} = driver, id, actions, aim \\ nil, strength \\ %{}) do
    input = %{held: MapSet.new(actions), aim: aim}
    input = if strength == %{}, do: input, else: Map.put(input, :strength, strength)
    %{driver | pending: Map.put(driver.pending, id, input)}
  end

  @doc "Run `count` ticks."
  @spec tick(t(), pos_integer()) :: t()
  def tick(%__MODULE__{} = driver, count \\ 1),
    do: Enum.reduce(1..count//1, driver, fn _, acc -> once(acc) end)

  defp once(driver) do
    state =
      Enum.reduce(driver.pending, driver.state, fn {id, input}, state ->
        driver.game.handle_input(state, id, input)
      end)

    {events, state} = state |> driver.game.step(driver.dt) |> driver.game.drain_events()

    %{
      driver
      | state: state,
        pending: %{},
        events: driver.events ++ events,
        ticks: driver.ticks + 1
    }
  end

  @doc "Tick until `condition` holds of the driver, at most `limit` times; `{:timeout, driver}` when it never did."
  @spec until(t(), (t() -> boolean()), pos_integer()) :: {:ok, t()} | {:timeout, t()}
  def until(%__MODULE__{} = driver, condition, limit) do
    Enum.reduce_while(1..limit//1, driver, fn _, acc ->
      ticked = once(acc)
      if condition.(ticked), do: {:halt, {:ok, ticked}}, else: {:cont, ticked}
    end)
    |> case do
      {:ok, reached} -> {:ok, reached}
      %__MODULE__{} = last -> {:timeout, last}
    end
  end

  @doc "The game's view for player `id` now."
  @spec view(t(), term()) :: term()
  def view(%__MODULE__{} = driver, id), do: driver.game.view(driver.state, id)

  @doc "Every event drained so far, oldest first."
  @spec events(t()) :: [term()]
  def events(%__MODULE__{events: events}), do: events

  @doc "The game's state."
  @spec state(t()) :: term()
  def state(%__MODULE__{state: state}), do: state

  @doc "How many ticks have run."
  @spec tick_count(t()) :: non_neg_integer()
  def tick_count(%__MODULE__{ticks: ticks}), do: ticks
end
