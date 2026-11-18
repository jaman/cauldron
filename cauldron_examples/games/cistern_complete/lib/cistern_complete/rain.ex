defmodule CisternComplete.Rain do
  @moduledoc """
  The rain in a square: drops the Squall lets go, the burst at the end of a sulk, and
  what becomes of each as it falls.

  A drop is `%{x, y, kind}`, `kind` `:rain` or `:hail`. Rain in a jar's mouth fills the
  jar, or goes straight to the cistern while the keeper pours; rain into a full jar
  spills, and that is a miss, as rain reaching the ground is. Hail in a jar's mouth breaks
  the jar; hail on the ground bounces away harmlessly.
  """

  alias Cauldron.{Rng, Tuning}
  alias CisternComplete.{Field, Mishap, Squall, Storm, Yoke}

  @start 1.6
  @ground 10.2
  @burst [-2.0, -1.0, 0.0, 1.0, 2.0]

  @doc "The field after the Squall's rain of `dt` seconds is let go, and the events of it."
  @spec release({Field.t(), [term()]}, number(), Storm.t()) :: {Field.t(), [term()]}
  def release({%{lull: lull} = field, events}, dt, _pace) when lull > 0,
    do: {%{field | lull: max(0.0, lull - dt)}, events}

  def release({field, events}, dt, pace) do
    left = field.until_drop - dt

    case Squall.drop_rate(field.squall) do
      nil -> {field, events}
      _rate when field.released >= pace.drops -> {field, events}
      _rate when left > 0 -> {%{field | until_drop: left}, events}
      rate -> let_go({field, events}, [field.squall.x], pace, pace.drop_every / rate)
    end
  end

  @doc "The field after a sulk's burst: a spread of drops beneath the Squall at once."
  @spec burst({Field.t(), [term()]}, Storm.t()) :: {Field.t(), [term()]}
  def burst({field, events}, pace) do
    spread = for offset <- @burst, x = field.squall.x + offset, x > 0.5 and x < 15.5, do: x

    let_go(
      {field, [{:burst, Field.place(field, %{x: field.squall.x, y: 1.0})} | events]},
      spread,
      pace,
      field.until_drop
    )
  end

  @doc "The field after its drops fall for `dt` seconds."
  @spec fall({Field.t(), [term()]}, number(), Storm.t(), Tuning.t()) :: {Field.t(), [term()]}
  def fall({field, events}, dt, pace, tuning) do
    moved = Enum.map(field.drops, &%{&1 | y: &1.y + pace.fall * dt})
    each({%{field | drops: []}, events}, moved, tuning)
  end

  defp each(acc, [], _tuning), do: acc

  defp each({field, events}, [drop | rest], tuning) do
    {landed, events} = land({field, events}, drop, tuning)

    if landed.lull > field.lull,
      do: {%{landed | splashes: Enum.map(rest, &splash/1) ++ landed.splashes}, events},
      else: each({landed, events}, rest, tuning)
  end

  defp splash(drop), do: %{x: drop.x, y: drop.y, age: 0.0}

  defp let_go({field, events}, xs, pace, next_in) do
    {drops, rng} =
      Enum.map_reduce(xs, field.rng, fn x, rng ->
        {roll, rng} = Rng.roll(rng, 1000)
        {%{x: x, y: @start, kind: if(roll <= pace.hail * 1000, do: :hail, else: :rain)}, rng}
      end)

    released = %{
      field
      | rng: rng,
        drops: drops ++ field.drops,
        released: field.released + length(drops),
        until_drop: next_in
    }

    {released, Enum.map(drops, &{&1.kind, Field.place(field, &1)}) ++ events}
  end

  defp land({field, events}, drop, tuning) do
    case {Yoke.catching(field.yoke, drop), drop.kind} do
      {nil, _kind} when drop.y >= @ground -> grounded({field, events}, drop, tuning)
      {nil, _kind} -> {%{field | drops: [drop | field.drops]}, events}
      {jar, :hail} -> Mishap.hail({field, events}, drop, jar.slot)
      {jar, :rain} -> caught({field, events}, drop, jar, tuning)
    end
  end

  defp grounded({field, events}, %{kind: :hail} = drop, _tuning),
    do: {field, [{:bounce, Field.place(field, drop)} | events]}

  defp grounded(acc, drop, tuning), do: Mishap.miss(acc, drop, tuning)

  defp caught({%{pouring: pouring} = field, events}, drop, _jar, _tuning) when pouring > 0,
    do: {%{field | water: field.water + 1}, [{:catch, Field.place(field, drop)} | events]}

  defp caught({field, events}, drop, jar, tuning) do
    if jar.fill >= Tuning.get(tuning, :capacity) do
      Mishap.miss({field, [{:spill, Field.place(field, drop)} | events]}, drop, tuning)
    else
      filled = %{field | yoke: Yoke.fill(field.yoke, jar.slot), streak: field.streak + 1}
      mend({filled, [{:catch, Field.place(field, drop)} | events]}, tuning)
    end
  end

  defp mend({field, events}, tuning) do
    with true <- field.streak >= Tuning.get(tuning, :streak),
         %Yoke{} = mended <- Yoke.mend(field.yoke) do
      {%{field | yoke: mended, streak: 0},
       [{:mend, Field.place(field, %{x: mended.centre, y: 10})} | events]}
    else
      _no_mend -> {field, events}
    end
  end
end
