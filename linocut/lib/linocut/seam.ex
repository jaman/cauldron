defmodule Linocut.Seam do
  @moduledoc """
  A picture made to repeat without a visible join.

      Linocut.Seam.close(raster, x: 24, y: 16)

  Closing an axis fades that many pixels of the far edge into the near edge and drops the
  pixels it borrowed, so the result is narrower or shorter by that much and its edges
  match. A picture closed on an axis tiles along it.
  """

  alias FrenchCurve.Raster

  @doc """
  `raster` with its edges faded together.

  ## Options

    * `:x` — pixels to blend across the left and right edges. Default `0`
    * `:y` — pixels to blend across the top and bottom edges. Default `0`
  """
  @spec close(Raster.t(), keyword()) :: Raster.t()
  def close(raster, opts \\ []) do
    raster
    |> vertical(Keyword.get(opts, :y, 0))
    |> horizontal(Keyword.get(opts, :x, 0))
  end

  defp vertical(raster, blend) when blend < 1, do: raster

  defp vertical(%Raster{width: width, height: height} = raster, blend) when blend * 2 < height do
    source = Raster.to_rgba_binary(raster)
    stride = width * 4
    kept = height - blend

    rgba =
      for y <- 0..(kept - 1)//1, into: <<>> do
        row = binary_part(source, y * stride, stride)

        if y < blend do
          mix(row, binary_part(source, (kept + y) * stride, stride), 1 - y / blend)
        else
          row
        end
      end

    Raster.from_rgba(width, kept, rgba)
  end

  defp vertical(raster, _blend), do: raster

  defp horizontal(raster, blend) when blend < 1, do: raster

  defp horizontal(%Raster{width: width} = raster, blend) when blend * 2 < width do
    raster
    |> Linocut.rotate(90)
    |> vertical(blend)
    |> Linocut.rotate(270)
  end

  defp horizontal(raster, _blend), do: raster

  defp mix(near, far, weight) do
    near
    |> pixels()
    |> Enum.zip(pixels(far))
    |> Enum.map_join(fn {<<nr, ng, nb, na>>, <<fr, fg, fb, fa>>} ->
      <<blend(nr, fr, weight), blend(ng, fg, weight), blend(nb, fb, weight),
        blend(na, fa, weight)>>
    end)
  end

  defp pixels(binary), do: for(<<pixel::binary-size(4) <- binary>>, do: pixel)

  defp blend(near, far, weight), do: round(near * (1 - weight) + far * weight)
end
