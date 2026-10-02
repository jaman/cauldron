defmodule Cauldron2D.Parallax.Scatter do
  @moduledoc """
  A cell function that places art by hashing the tile's own coordinate.

      Cauldron2D.Parallax.Scatter.cells(seed: 7, density: 0.08, arts: [:pine, {:boulder, 1}])

  The function answers for any coordinate, keeps no state, and gives the same answer every
  time it is asked and on every node, so a scattered layer never has to be sent anywhere.
  """

  import Bitwise

  @type art :: term()
  @type cell :: :void | {art(), [art()], nil}

  @mask 0xFFFFFFFFFFFFFFFF
  @resolution 1_000_000

  @doc """
  Build the cell function.

  ## Options

    * `:arts` — what to place, as `[art | {art, weight}]`, required and not empty. A bare
      art counts as weight 1
    * `:seed` — this layer's own seed. Default `0`
    * `:density` — the fraction of tiles holding art, `0.0..1.0`. Default `0.05`
    * `:rows` — a range of tile rows art may stand in. Default every row
  """
  @spec cells(keyword()) :: ({integer(), integer()} -> cell())
  def cells(opts) do
    arts = opts |> Keyword.fetch!(:arts) |> weighted()
    total = arts |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    seed = Keyword.get(opts, :seed, 0)
    threshold = round(Keyword.get(opts, :density, 0.05) * @resolution)
    rows = Keyword.get(opts, :rows)

    fn {x, y} ->
      cond do
        rows != nil and not Enum.member?(rows, y) -> :void
        rem(hash(seed, x, y), @resolution) >= threshold -> :void
        true -> {draw(arts, rem(hash(seed + 1, x, y), total)), [], nil}
      end
    end
  end

  @doc "The same hash the cell function draws from, for a caller placing its own things."
  @spec draw_at(integer(), integer(), integer()) :: non_neg_integer()
  def draw_at(seed, x, y), do: hash(seed, x, y)

  defp weighted([]), do: raise(ArgumentError, "a scatter needs at least one art")

  defp weighted(arts) do
    Enum.map(arts, fn
      {art, weight} when is_integer(weight) and weight > 0 -> {art, weight}
      art -> {art, 1}
    end)
  end

  defp draw([{art, _weight}], _roll), do: art

  defp draw([{art, weight} | rest], roll) do
    if roll < weight, do: art, else: draw(rest, roll - weight)
  end

  defp hash(seed, x, y) do
    (seed * 0x9E3779B97F4A7C15 + x * 0xBF58476D1CE4E5B9 + y * 0x94D049BB133111EB)
    |> band(@mask)
    |> scramble()
  end

  defp scramble(value) do
    value
    |> bxor(bsr(value, 30))
    |> Kernel.*(0xBF58476D1CE4E5B9)
    |> band(@mask)
    |> then(fn v -> v |> bxor(bsr(v, 27)) |> Kernel.*(0x94D049BB133111EB) |> band(@mask) end)
    |> then(fn v -> bxor(v, bsr(v, 31)) end)
  end
end
