defmodule Cauldron2D.Rng do
  @moduledoc """
  A random number generator carried in a game's state rather than the process dictionary.

  Every function here takes a generator and returns `{value, next_generator}`. A caller must
  thread the returned generator into the following call; reusing an earlier one repeats its
  values. Given the same seed and the same sequence of calls, a run replays exactly.

  Wraps `:rand`'s stateful API on the `:exsss` algorithm.

      rng = Cauldron2D.Rng.new(1234)
      {damage, rng} = Cauldron2D.Rng.dice(rng, 2, 6)
      {critical?, _rng} = Cauldron2D.Rng.chance(rng, 1, 20)
  """

  @type t :: :rand.state()

  @algorithm :exsss

  @doc "A generator seeded from `seed`, which may be any integer."
  @spec new(integer()) :: t()
  def new(seed) when is_integer(seed) do
    :rand.seed_s(@algorithm, {seed, seed * 2 + 1, seed * 3 + 7})
  end

  @doc """
  A generator seeded from the system clock, and the seed it used.

  Keep the returned seed to replay the same run through `new/1`.
  """
  @spec random() :: {t(), integer()}
  def random do
    seed = :erlang.unique_integer([:positive]) + System.system_time(:microsecond)
    {new(seed), seed}
  end

  @doc "An integer in `1..n`, uniformly. `n` must be at least 1."
  @spec roll(t(), pos_integer()) :: {pos_integer(), t()}
  def roll(rng, n) when n >= 1, do: :rand.uniform_s(n, rng)

  @doc "An integer in `lo..hi`, inclusive, uniformly. `hi` must not be less than `lo`."
  @spec between(t(), integer(), integer()) :: {integer(), t()}
  def between(rng, lo, hi) when hi >= lo do
    {n, rng} = roll(rng, hi - lo + 1)
    {lo + n - 1, rng}
  end

  @doc "The sum of `count` independent rolls of a die with `sides` faces."
  @spec dice(t(), pos_integer(), pos_integer()) :: {pos_integer(), t()}
  def dice(rng, count, sides) do
    Enum.reduce(1..count//1, {0, rng}, fn _, {total, rng} ->
      {n, rng} = roll(rng, sides)
      {total + n, rng}
    end)
  end

  @doc "True with probability `numerator / denominator`. Both must be positive integers."
  @spec chance(t(), pos_integer(), pos_integer()) :: {boolean(), t()}
  def chance(rng, numerator, denominator) do
    {n, rng} = roll(rng, denominator)
    {n <= numerator, rng}
  end

  @doc "One element of `list`, each equally likely, or `nil` when `list` is empty."
  @spec pick(t(), [term()]) :: {term() | nil, t()}
  def pick(rng, []), do: {nil, rng}

  def pick(rng, list) do
    {n, rng} = roll(rng, length(list))
    {Enum.at(list, n - 1), rng}
  end

  @doc """
  One value from a list of `{weight, value}` pairs, chosen in proportion to the weights.

  Weights are relative and need not sum to anything in particular. Each must be a non-negative
  integer, and at least one must be positive; a weight of `0` is a value that is never chosen.
  Returns `nil` for an empty list.

  Raises `ArgumentError` on a weight that is not a non-negative integer, and on a list whose
  weights are all zero — a list that cannot answer, rather than one that answers oddly.
  """
  @spec weighted(t(), [{non_neg_integer(), term()}]) :: {term() | nil, t()}
  def weighted(rng, []), do: {nil, rng}

  def weighted(rng, pairs) do
    total = Enum.sum_by(pairs, &weight/1)

    if total == 0 do
      raise ArgumentError,
            "weighted/2 needs at least one positive weight, got all zero: #{inspect(pairs)}"
    end

    {roll, rng} = roll(rng, total)
    {take_weighted(pairs, roll), rng}
  end

  defp weight({weight, _value}) when is_integer(weight) and weight >= 0, do: weight

  defp weight({weight, _value}) do
    raise ArgumentError,
          "weighted/2 needs non-negative integer weights, got: #{inspect(weight)}"
  end

  defp weight(pair) do
    raise ArgumentError, "weighted/2 takes {weight, value} pairs, got: #{inspect(pair)}"
  end

  defp take_weighted([{weight, value} | rest], roll) do
    if roll <= weight, do: value, else: take_weighted(rest, roll - weight)
  end

  @doc """
  The elements of `list` in a random order.

  A Fisher-Yates shuffle, so every ordering is equally likely however long the list is. Costs
  one roll per element.
  """
  @spec shuffle(t(), [term()]) :: {[term()], t()}
  def shuffle(rng, list) when length(list) < 2, do: {list, rng}

  def shuffle(rng, list) do
    count = length(list)
    indexed = list |> Enum.with_index() |> Map.new(fn {item, index} -> {index, item} end)
    {shuffled, rng} = fisher_yates(indexed, count - 1, rng)

    {Enum.map(0..(count - 1), &Map.fetch!(shuffled, &1)), rng}
  end

  defp fisher_yates(items, 0, rng), do: {items, rng}

  defp fisher_yates(items, at, rng) do
    {roll, rng} = roll(rng, at + 1)
    other = roll - 1

    items
    |> Map.put(at, Map.fetch!(items, other))
    |> Map.put(other, Map.fetch!(items, at))
    |> fisher_yates(at - 1, rng)
  end
end
