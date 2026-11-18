defmodule Cauldron.Effects do
  @moduledoc """
  Effects that play once and go — a blast, a splash, a puff of dust — as maps a game
  keeps in its state, each with an `:age` in seconds and whatever else it draws by (where,
  how big). An effect with a negative age has not begun: it waits that long, so a
  group of effects can go off one after another.

      blasts = [%{x: 3.0, y: 4.0, age: 0.0}, %{x: 5.0, y: 4.0, age: -0.2}]
      blasts = Cauldron.Effects.step(blasts, dt, 0.5)
      frame = Cauldron.Effects.frame(blast, 4, 8.0)
  """

  @type effect :: %{required(:age) => number(), optional(atom()) => term()}

  @doc "The effects `dt` seconds older, those that have lived `seconds` gone."
  @spec step([effect()], number(), number()) :: [effect()]
  def step(effects, dt, seconds),
    do: for(effect <- effects, effect.age + dt < seconds, do: %{effect | age: effect.age + dt})

  @doc "The frame of an effect's `frames` to show at its age, at `fps` frames a second, from `0`; the first before it has begun and the last once it has run through them."
  @spec frame(effect(), pos_integer(), number()) :: non_neg_integer()
  def frame(effect, frames, fps), do: min(frames - 1, trunc(max(0.0, effect.age) * fps))
end
