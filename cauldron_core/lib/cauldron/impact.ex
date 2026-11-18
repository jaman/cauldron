defmodule Cauldron.Impact do
  @moduledoc """
  The weight of a hit: the world held still a moment (hit-stop) and the view shaken, as a
  value a game keeps in its state.

    * `freeze/2` — hold the world still for at least the given seconds
    * `shake/2` — shake the view at least this hard; it dies away by a unit a second
    * `step/2` — run both down; while frozen only the freeze runs down
    * `frozen?/1` — whether the world should hold still this step
    * `offset/2` — where a shake of that strength moves the view at a clock time; it
      depends only on the clock, so a replay shakes the same

      impact = world.impact |> Impact.freeze(0.08) |> Impact.shake(0.3)

      def step(world, dt) do
        if Impact.frozen?(world.impact),
          do: %{world | impact: Impact.step(world.impact, dt)},
          else: run(%{world | impact: Impact.step(world.impact, dt)}, dt)
      end

      {dx, dy} = Impact.offset(view.shake, view.clock)
  """

  defstruct frozen: 0.0, shake: 0.0

  @type t :: %__MODULE__{frozen: number(), shake: number()}

  @doc "No freeze, no shake."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "`impact` frozen for at least `seconds` from now."
  @spec freeze(t(), number()) :: t()
  def freeze(impact, seconds), do: %{impact | frozen: max(impact.frozen, seconds)}

  @doc "`impact` shaking at least `amount` hard."
  @spec shake(t(), number()) :: t()
  def shake(impact, amount), do: %{impact | shake: max(impact.shake, amount)}

  @doc "Whether the world holds still."
  @spec frozen?(t()) :: boolean()
  def frozen?(impact), do: impact.frozen > 0

  @doc "`impact` `dt` seconds on: the freeze run down while it lasts, else the shake."
  @spec step(t(), number()) :: t()
  def step(%{frozen: frozen} = impact, dt) when frozen > 0,
    do: %{impact | frozen: max(0.0, frozen - dt)}

  def step(impact, dt), do: %{impact | shake: max(0.0, impact.shake - dt)}

  @doc "The view's shift `{dx, dy}` in tiles for a shake of `amount` at clock time `clock` (seconds)."
  @spec offset(number(), number()) :: {float(), float()}
  def offset(amount, clock),
    do: {:math.sin(clock * 70.0) * amount * 0.4, :math.cos(clock * 50.0) * amount * 0.4}
end
