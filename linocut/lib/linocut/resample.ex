defmodule Linocut.Resample do
  @moduledoc """
  A picture redrawn at another size.

      Linocut.Resample.to(raster, {320, 180})
      Linocut.Resample.to(raster, {320, 180}, mode: :nearest)

  `:area` averages the source pixels each target pixel covers, weighted by their alpha, so
  a shrunk picture keeps its edges where they were. `:nearest` takes the one source pixel
  at the middle of that area, which keeps hard pixel art hard.
  """

  alias FrenchCurve.Raster

  @type mode :: :area | :nearest

  @doc """
  `raster` at `{width, height}`.

  ## Options

    * `:mode` — `:area` or `:nearest`. Default `:area`
  """
  @spec to(Raster.t(), {pos_integer(), pos_integer()}, keyword()) :: Raster.t()
  def to(raster, size, opts \\ [])

  def to(%Raster{width: width, height: height} = raster, {width, height}, _opts), do: raster

  def to(%Raster{} = raster, {width, height}, opts)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    source = Raster.to_rgba_binary(raster)
    mode = Keyword.get(opts, :mode, :area)

    rgba =
      for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, into: <<>> do
        pixel(mode, source, raster, {x, y}, {width, height})
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp pixel(:nearest, source, raster, {x, y}, {width, height}) do
    sx = min(raster.width - 1, div((2 * x + 1) * raster.width, 2 * width))
    sy = min(raster.height - 1, div((2 * y + 1) * raster.height, 2 * height))

    binary_part(source, (sy * raster.width + sx) * 4, 4)
  end

  defp pixel(:area, source, raster, {x, y}, {width, height}) do
    x0 = div(x * raster.width, width)
    x1 = max(x0 + 1, div((x + 1) * raster.width, width))
    y0 = div(y * raster.height, height)
    y1 = max(y0 + 1, div((y + 1) * raster.height, height))

    {r, g, b, a, count} =
      for sy <- y0..(min(y1, raster.height) - 1)//1,
          sx <- x0..(min(x1, raster.width) - 1)//1,
          reduce: {0, 0, 0, 0, 0} do
        {r, g, b, a, count} ->
          <<pr, pg, pb, pa>> = binary_part(source, (sy * raster.width + sx) * 4, 4)
          {r + pr * pa, g + pg * pa, b + pb * pa, a + pa, count + 1}
      end

    average({r, g, b, a}, count)
  end

  defp average({_r, _g, _b, 0}, _count), do: <<0, 0, 0, 0>>

  defp average({r, g, b, a}, count),
    do: <<div(r, a), div(g, a), div(b, a), div(a, count)>>
end
