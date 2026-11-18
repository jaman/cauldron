defmodule Cauldron.Tween do
  @moduledoc """
  A value moving from one number — or point, or colour — to another over a time, along an
  easing curve (`Cauldron.Ease`), kept in the game's state and stepped with it: a door
  sliding open, a title dropping in, a fade.

      fade = Cauldron.Tween.new(0.0, 1.0, 0.6, :out_quad)
      fade = Cauldron.Tween.step(fade, dt)
      Cauldron.Tween.value(fade)
      Cauldron.Tween.done?(fade)

  `from` and `to` are numbers, or tuples of numbers of the same size (`{x, y}`,
  `{r, g, b}`), moved element by element. A tween of no duration is at its end at once.
  """

  @enforce_keys [:from, :to, :seconds]
  defstruct [:from, :to, :seconds, curve: :linear, t: 0.0]

  @type value :: number() | tuple()
  @type t :: %__MODULE__{
          from: value(),
          to: value(),
          seconds: number(),
          curve: Cauldron.Ease.curve(),
          t: number()
        }

  @doc "A tween from `from` to `to` over `seconds`, along `curve` (default `:linear`)."
  @spec new(value(), value(), number(), Cauldron.Ease.curve()) :: t()
  def new(from, to, seconds, curve \\ :linear),
    do: %__MODULE__{from: from, to: to, seconds: seconds, curve: curve}

  @doc "The tween `dt` seconds on, stopping at its end."
  @spec step(t(), number()) :: t()
  def step(tween, dt), do: %{tween | t: min(tween.seconds, tween.t + dt)}

  @doc "Whether the tween has reached its end."
  @spec done?(t()) :: boolean()
  def done?(tween), do: tween.t >= tween.seconds

  @doc "Where the value is now."
  @spec value(t()) :: value()
  def value(%{seconds: seconds} = tween) when seconds <= 0, do: tween.to

  def value(tween) do
    share = Cauldron.Ease.apply(tween.curve, tween.t / tween.seconds)
    between(tween.from, tween.to, share)
  end

  defp between(from, to, share) when is_number(from), do: from + (to - from) * share

  defp between(from, to, share) when is_tuple(from) do
    [Tuple.to_list(from), Tuple.to_list(to)]
    |> Enum.zip_with(fn [a, b] -> between(a, b, share) end)
    |> List.to_tuple()
  end
end
