defmodule Linocut.SeamTest do
  @moduledoc """
  Closing a picture's edges: what it costs in size and how near the edges end up.
  """

  use ExUnit.Case, async: true

  alias FrenchCurve.Raster
  alias Linocut.Seam

  describe "close/2" do
    test "closing an axis shortens the picture by the blend" do
      raster = ramp(32, 64)

      assert Raster.dimensions(Seam.close(raster, y: 8)) == {32, 56}
      assert Raster.dimensions(Seam.close(raster, x: 6)) == {26, 64}
      assert Raster.dimensions(Seam.close(raster, x: 6, y: 8)) == {26, 56}
    end

    test "closing nothing leaves the picture alone" do
      raster = ramp(16, 16)

      assert Seam.close(raster) == raster
      assert Seam.close(raster, x: 0, y: 0) == raster
    end

    test "the bottom edge ends up near the top edge" do
      raster = ramp(8, 64)
      closed = Seam.close(raster, y: 12)

      assert gap(raster, 0, raster.height - 1) > 200
      assert gap(closed, 0, closed.height - 1) < 40
    end

    test "the right edge ends up near the left edge" do
      raster = ramp_across(64, 8)
      closed = Seam.close(raster, x: 12)

      assert across(raster, 0, raster.width - 1) > 200
      assert across(closed, 0, closed.width - 1) < 40
    end

    test "a blend wider than the picture leaves it alone" do
      raster = ramp(8, 8)

      assert Seam.close(raster, y: 40) == raster
      assert Seam.close(raster, x: 40) == raster
    end
  end

  defp ramp(width, height) do
    rgba =
      for y <- 0..(height - 1), _x <- 0..(width - 1), into: <<>> do
        value = round(y * 255 / (height - 1))
        <<value, value, value, 255>>
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp ramp_across(width, height) do
    rgba =
      for _y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        value = round(x * 255 / (width - 1))
        <<value, value, value, 255>>
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp gap(raster, top, bottom) do
    {r, _g, _b, _a} = Raster.get_pixel(raster, 0, top)
    {other, _g, _b, _a} = Raster.get_pixel(raster, 0, bottom)
    abs(r - other)
  end

  defp across(raster, left, right) do
    {r, _g, _b, _a} = Raster.get_pixel(raster, left, 0)
    {other, _g, _b, _a} = Raster.get_pixel(raster, right, 0)
    abs(r - other)
  end
end
