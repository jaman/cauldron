defmodule CisternComplete.Lightning do
  @moduledoc """
  Lightning in the storms that bring it: every so often a column near the keeper
  flickers, and when the flicker ends it strikes. A keeper still under it loses a jar;
  one who stepped out of the column is safe.

  A field's `strike` is `nil`, or `%{x, left}` while a column flickers, `left` the
  seconds until it strikes. Its `bolts` are the strikes still showing, `%{x, age}`.
  """

  alias Cauldron.{Rng, Tuning}
  alias CisternComplete.{Field, Mishap, Storm}

  @reach 1.0
  @bolt_seconds 0.35

  @doc "The field `dt` seconds on: a flicker begun, a strike made, or the wait counted down."
  @spec step({Field.t(), [term()]}, number(), Storm.t(), Tuning.t()) :: {Field.t(), [term()]}
  def step({field, events}, dt, %{lightning?: true}, tuning) when field.lull == 0 do
    field = %{field | bolts: age(field.bolts, dt)}

    case field.strike do
      nil ->
        wait({field, events}, dt, tuning)

      %{left: left} = strike when left > dt ->
        {%{field | strike: %{strike | left: left - dt}}, events}

      %{x: x} ->
        strike(
          {%{field | strike: nil, until_strike: Tuning.get(tuning, :lightning_every)}, events},
          x
        )
    end
  end

  def step({field, events}, dt, _pace, _tuning),
    do: {%{field | bolts: age(field.bolts, dt)}, events}

  defp wait({field, events}, dt, tuning) do
    left = field.until_strike - dt

    if left > 0 do
      {%{field | until_strike: left}, events}
    else
      {offset, rng} = Rng.between(field.rng, -2, 2)
      x = (field.yoke.centre + offset) |> max(0.5) |> min(15.5)
      strike = %{x: x, left: Tuning.get(tuning, :flicker)}

      {%{field | rng: rng, strike: strike},
       [{:flicker, Field.place(field, %{x: x, y: 5})} | events]}
    end
  end

  defp strike({field, events}, x) do
    struck = %{field | bolts: [%{x: x, age: 0.0} | field.bolts]}
    events = [{:thunder, Field.place(field, %{x: x, y: 5})} | events]

    if abs(field.yoke.centre - x) < @reach,
      do: Mishap.bolt({struck, events}, x),
      else: {struck, events}
  end

  defp age(bolts, dt), do: Cauldron.Effects.step(bolts, dt, @bolt_seconds)
end
