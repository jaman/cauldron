defmodule Cauldron.Noise do
  @moduledoc """
  Smooth random values over the plane. The same seed and point give the same value on
  every machine and every run.

      Cauldron.Noise.at(7, 12.5, 3.25)
      Cauldron.Noise.fractal(7, 12.5, 3.25, octaves: 5, gain: 0.5, lacunarity: 2.0)

  `at/3` changes by about one whole swing for each unit travelled and is zero at whole
  coordinates. `fractal/4` adds `:octaves` (default 4) layers of it, each `:lacunarity`
  (default 2.0) times finer and `:gain` (default 0.5) times weaker than the last. Both
  stay between -1.0 and 1.0.
  """

  @doc "The value at `{x, y}` for `seed`."
  @spec at(integer(), number(), number()) :: float()
  def at(seed, x, y) do
    {left, bottom} = {floor(x), floor(y)}
    {right, up} = {x - left, y - bottom}
    {across, along} = {fade(right), fade(up)}

    low =
      blend(pull(seed, left, bottom, right, up), pull(seed, left + 1, bottom, right - 1, up), across)

    high =
      blend(
        pull(seed, left, bottom + 1, right, up - 1),
        pull(seed, left + 1, bottom + 1, right - 1, up - 1),
        across
      )

    (blend(low, high, along) * 1.41421356) |> max(-1.0) |> min(1.0)
  end

  @doc "Layers of `at/3` summed at `{x, y}` for `seed`."
  @spec fractal(integer(), number(), number(), keyword()) :: float()
  def fractal(seed, x, y, opts \\ []) do
    octaves = Keyword.get(opts, :octaves, 4)
    gain = Keyword.get(opts, :gain, 0.5)
    lacunarity = Keyword.get(opts, :lacunarity, 2.0)

    {sum, reach} =
      Enum.reduce(0..(octaves - 1)//1, {0.0, 0.0}, fn octave, {sum, reach} ->
        weight = :math.pow(gain, octave)
        scale = :math.pow(lacunarity, octave)
        {sum + weight * at(seed + octave, x * scale, y * scale), reach + weight}
      end)

    if reach > 0.0, do: sum / reach, else: 0.0
  end

  defp pull(seed, column, row, right, up) do
    angle = :erlang.phash2({seed, column, row}, 1_000_000) * (2.0 * :math.pi() / 1_000_000)
    :math.cos(angle) * right + :math.sin(angle) * up
  end

  defp fade(t), do: t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
  defp blend(from, to, amount), do: from + (to - from) * amount
end
