defmodule Linocut.PixelateTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster
  alias Linocut.Pixelate

  @colours [{200, 60, 40}, {40, 120, 200}, {240, 220, 120}]

  defp art(width, height) do
    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        {r, g, b} = Enum.at(@colours, rem(x * 7 + y * 3 + div(x * y, 5), 3))
        <<r, g, b, 255>>
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp drawn_large(raster, scale) do
    width = trunc(raster.width * scale)
    height = trunc(raster.height * scale)
    source = Raster.to_rgba_binary(raster)

    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        binary_part(source, (trunc(y / scale) * raster.width + trunc(x / scale)) * 4, 4)
      end

    Raster.from_rgba(width, height, rgba)
  end

  test "pixel art drawn large at a fractional scale is found on its grid and sampled back" do
    small = art(12, 10)
    large = drawn_large(small, 8.6)

    %{cell: {across, down}} = grid = Pixelate.grid(large)
    assert_in_delta across, 8.6, 0.05
    assert_in_delta down, 8.6, 0.05

    assert Pixelate.sample(large, grid) |> Raster.to_rgba_binary() ==
             Raster.to_rgba_binary(small)
  end
end
