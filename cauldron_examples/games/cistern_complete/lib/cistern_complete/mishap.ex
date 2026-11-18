defmodule CisternComplete.Mishap do
  @moduledoc """
  What goes wrong in a square, and what it costs.

    * `miss/3` — rain reached the ground, or spilled from a full jar: the jar on that
      side breaks, every drop still falling splashes, the storm steps back and goes quiet
      a moment, and the Squall grins
    * `hail/3` — hail landed in a jar: that jar breaks, and the storm goes on
    * `bolt/3` — lightning struck the keeper: the jar on the side it struck breaks

  A keeper whose head jar breaks is out. Each answers the field and its events added
  to `events`, newest first.
  """

  alias Cauldron.Tuning
  alias CisternComplete.{Field, Squall, Yoke}

  @doc "The field after a miss by `drop`."
  @spec miss({Field.t(), [term()]}, map(), Tuning.t()) :: {Field.t(), [term()]}
  def miss({field, events}, drop, tuning) do
    splashes = Enum.map([drop | field.drops], &%{x: &1.x, y: min(&1.y, 10.2), age: 0.0})
    yoke = Yoke.break(field.yoke, side(field, drop.x))

    missed = %{
      field
      | yoke: yoke,
        drops: [],
        splashes: splashes ++ field.splashes,
        streak: 0,
        level: max(1, field.level - 1),
        released: 0,
        until_drop: 0.0,
        lull: Tuning.get(tuning, :lull),
        strike: nil,
        squall: Squall.grin(field.squall)
    }

    out(missed, [{:miss, Field.place(field, %{drop | y: 11})} | events])
  end

  @doc "The field after hail landed in jar `slot`."
  @spec hail({Field.t(), [term()]}, map(), Yoke.slot()) :: {Field.t(), [term()]}
  def hail({field, events}, drop, slot) do
    cracked = %{field | yoke: Yoke.break_jar(field.yoke, slot), streak: 0}
    out(cracked, [{:crack, Field.place(field, drop)} | events])
  end

  @doc "The field after lightning struck at column `x`."
  @spec bolt({Field.t(), [term()]}, number()) :: {Field.t(), [term()]}
  def bolt({field, events}, x) do
    struck = %{field | yoke: Yoke.break(field.yoke, side(field, x)), streak: 0}
    out(struck, [{:crack, Field.place(field, %{x: x, y: 9.0})} | events])
  end

  defp side(field, x), do: if(x < field.yoke.centre, do: :left, else: :right)

  defp out(field, events) do
    if Yoke.count(field.yoke) == 0,
      do: {%{field | out?: true}, [{:out, field.id} | events]},
      else: {field, events}
  end
end
