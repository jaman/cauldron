defmodule Cauldron.Presses do
  @moduledoc """
  The presses and releases in a player's held actions from one step to the next, and a
  short memory of recent presses, kept by a game with each player (a value in its
  state; no process).

  A game compares this step's held actions with the presses value it kept: `pressed/2`
  is what was taken up since the last step, `released/2` what was let go. `settle/3`,
  called once a step after the game has acted on them, remembers this step's held actions
  and how long ago each action was last pressed.

  `buffered?/4` is whether an action was pressed within a window of seconds, this step
  or a recent one: a press made a moment before it can count — a jump pressed just
  before landing, the next blow of a combo pressed just before the last one ends. A game
  that acts on a buffered press calls `clear/2`, so the one press does the one thing.

      presses = Cauldron.Presses.new()
      held = MapSet.new([:jump])

      if Cauldron.Presses.buffered?(presses, held, :jump, 0.12) and grounded?,
        do: jump(...)

      presses = Cauldron.Presses.settle(presses, held, dt)
  """

  @forget 1.0

  defstruct last: MapSet.new(), ages: %{}, cleared: MapSet.new()

  @type action :: atom()
  @type t :: %__MODULE__{
          last: MapSet.t(action()),
          ages: %{action() => number()},
          cleared: MapSet.t(action())
        }

  @doc "Nothing held before, nothing pressed."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The actions in `held` that were not held at the last step, less those cleared this step."
  @spec pressed(t(), MapSet.t(action())) :: MapSet.t(action())
  def pressed(%__MODULE__{last: last, cleared: cleared}, held),
    do: held |> MapSet.difference(last) |> MapSet.difference(cleared)

  @doc "The actions held at the last step that are not in `held`."
  @spec released(t(), MapSet.t(action())) :: MapSet.t(action())
  def released(%__MODULE__{last: last}, held), do: MapSet.difference(last, held)

  @doc """
  Whether `action` was pressed within the last `window` seconds: pressed this step, or
  pressed at a step `settle/3` remembered and not cleared since.
  """
  @spec buffered?(t(), MapSet.t(action()), action(), number()) :: boolean()
  def buffered?(%__MODULE__{} = presses, held, action, window) do
    MapSet.member?(pressed(presses, held), action) or
      case Map.fetch(presses.ages, action) do
        {:ok, age} -> age <= window
        :error -> false
      end
  end

  @doc "`presses` with `action`'s press forgotten, so `buffered?/4` is false for it until it is pressed again."
  @spec clear(t(), action()) :: t()
  def clear(%__MODULE__{} = presses, action),
    do: %{
      presses
      | ages: Map.delete(presses.ages, action),
        cleared: MapSet.put(presses.cleared, action)
    }

  @doc """
  `presses` after a step of `dt` seconds in which `held` was held: `held` remembered for
  the next step's `pressed/2`, each action pressed this step aged `0`, every earlier press
  aged by `dt`, and presses older than a second forgotten.
  """
  @spec settle(t(), MapSet.t(action()), number()) :: t()
  def settle(%__MODULE__{} = presses, held, dt) do
    fresh = pressed(presses, held)

    ages =
      for {action, age} <- presses.ages, age + dt <= @forget, into: %{}, do: {action, age + dt}

    %{
      presses
      | last: held,
        ages: Enum.reduce(fresh, ages, &Map.put(&2, &1, 0.0)),
        cleared: MapSet.new()
    }
  end
end
