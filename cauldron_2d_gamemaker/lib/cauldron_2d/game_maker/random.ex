defmodule Cauldron2D.GameMaker.Random do
  @moduledoc """
  GameMaker's random numbers: the runtime's WELL512a generator, seeded as
  `random_set_seed` seeds it, giving what `random`, `random_range`, `irandom`,
  `irandom_range` and `choose` give.

      random = Random.new(1234)
      {value, random} = Random.random(random, 10)

  A seed fills every one of the sixteen words of state with
  `(seed × 0x343FD + 0x269EC3) >> 16` and starts at word 0. Each draw is one 32-bit
  output; `random(n)` is that output × 2⁻³² × n.
  """

  import Bitwise

  @enforce_keys [:state, :index, :seed]
  defstruct [:state, :index, :seed]

  @type t :: %__MODULE__{state: tuple(), index: 0..15, seed: integer()}

  @mask 0xDA442D24
  @words 0xFFFFFFFF
  @scale 1 / 4_294_967_296

  @doc "A generator seeded with `seed` (`random_set_seed`)."
  @spec new(integer()) :: t()
  def new(seed) do
    word = (seed * 0x343FD + 0x269EC3 &&& @words) >>> 16
    %__MODULE__{state: Tuple.duplicate(word, 16), index: 0, seed: seed}
  end

  @doc "The next 32-bit output, and the generator after it."
  @spec next(t()) :: {non_neg_integer(), t()}
  def next(%__MODULE__{state: state, index: index} = random) do
    a = elem(state, index)
    c = elem(state, index + 13 &&& 15)
    b = bxor(bxor(a, c), bxor(a <<< 16, c <<< 15)) &&& @words
    nine = elem(state, index + 9 &&& 15)
    c = bxor(nine, nine >>> 11)
    a = bxor(b, c)
    state = put_elem(state, index, a)
    d = bxor(a, a <<< 5 &&& @mask)
    index = index + 15 &&& 15
    old = elem(state, index)

    out =
      old
      |> bxor(b)
      |> bxor(d)
      |> bxor(old <<< 2)
      |> bxor(b <<< 18)
      |> bxor(c <<< 28)
      |> band(@words)

    {out, %{random | state: put_elem(state, index, out), index: index}}
  end

  @doc "A real from 0 up to `n` (`random(n)`)."
  @spec random(t(), number()) :: {float(), t()}
  def random(%__MODULE__{} = random, n) do
    {out, random} = next(random)
    {out * @scale * n, random}
  end

  @doc "A real from `low` up to `high` (`random_range`)."
  @spec random_range(t(), number(), number()) :: {float(), t()}
  def random_range(%__MODULE__{} = random, low, high) do
    {low, high} = if high > low, do: {low, high}, else: {high, low}
    {value, random} = random(random, high - low)
    {low + value, random}
  end

  @doc """
  A whole number from 0 to `n` inclusive, or from `n` to 0 when `n` is negative
  (`irandom(n)`): two outputs make a 63-bit number, the second's low 31 bits above the
  first's 32, taken modulo `|n| + 1` and given `n`'s sign.
  """
  @spec irandom(t(), number()) :: {integer(), t()}
  def irandom(%__MODULE__{} = random, n) do
    {low, random} = next(random)
    {high, random} = next(random)
    wide = (high &&& 0x7FFFFFFF) <<< 32 ||| low
    sign = if n >= 0, do: 1, else: -1
    {sign * rem(wide, abs(trunc(n)) + 1), random}
  end

  @doc "A whole number from `low` to `high` inclusive (`irandom_range`)."
  @spec irandom_range(t(), number(), number()) :: {integer(), t()}
  def irandom_range(%__MODULE__{} = random, low, high) do
    {low, high} = if high > low, do: {trunc(low), trunc(high)}, else: {trunc(high), trunc(low)}
    {value, random} = irandom(random, high - low)
    {low + value, random}
  end

  @doc "One of `values` (`choose`): one output modulo how many there are picks it."
  @spec choose(t(), [term(), ...]) :: {term(), t()}
  def choose(%__MODULE__{} = random, values) do
    {out, random} = next(random)
    {Enum.at(values, rem(out, length(values))), random}
  end
end
