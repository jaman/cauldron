defmodule Linocut.QuantiseTest do
  @moduledoc """
  Reducing a picture to a palette: how many colours come back, which ones, and what the
  reduced picture is made of.
  """

  use ExUnit.Case, async: true

  alias FrenchCurve.Raster
  alias Linocut.{Quantise, Resample}

  describe "palette/3" do
    test "never gives more colours than it was asked for" do
      raster = spread(64, 64)

      for count <- [2, 4, 8, 16, 32] do
        assert length(Quantise.palette(raster, count)) <= count
      end
    end

    test "a picture of two colours gives those two colours" do
      raster = stripes({10, 20, 30, 255}, {200, 210, 220, 255})

      assert Quantise.palette(raster, 8) == [{10, 20, 30}, {200, 210, 220}]
    end

    test "a picture of one colour gives one colour" do
      raster = Raster.new(8, 8, background: {40, 50, 60, 255})

      assert Quantise.palette(raster, 16) == [{40, 50, 60}]
    end

    test "clear pixels take no entry" do
      raster = stripes({10, 20, 30, 255}, {200, 210, 220, 0})

      assert Quantise.palette(raster, 8) == [{10, 20, 30}]
    end
  end

  describe "reduce/3" do
    test "every opaque pixel ends up as one of the palette's colours" do
      {reduced, palette} = Quantise.reduce(spread(64, 64), 8)
      colours = MapSet.new(palette)

      for <<r, g, b, a <- Raster.to_rgba_binary(reduced)>>, a > 0 do
        assert MapSet.member?(colours, {r, g, b})
      end
    end

    test "a clear pixel stays clear" do
      {reduced, _palette} = Quantise.reduce(stripes({10, 20, 30, 255}, {9, 9, 9, 0}), 4)

      assert binary_part(Raster.to_rgba_binary(reduced), 4, 4) == <<0, 0, 0, 0>>
    end
  end

  describe "Resample.to/3" do
    test "the picture comes back at the size asked for" do
      assert Raster.dimensions(Resample.to(spread(64, 32), {16, 8})) == {16, 8}
      assert Raster.dimensions(Resample.to(spread(7, 5), {21, 15}, mode: :nearest)) == {21, 15}
    end

    test "a picture of one colour stays that colour" do
      shrunk = Resample.to(Raster.new(64, 64, background: {12, 34, 56, 255}), {8, 8})

      assert Raster.to_rgba_binary(shrunk) == :binary.copy(<<12, 34, 56, 255>>, 64)
    end

    test "a clear picture stays clear" do
      shrunk = Resample.to(Raster.new(32, 32), {4, 4})

      assert Raster.to_rgba_binary(shrunk) == :binary.copy(<<0, 0, 0, 0>>, 16)
    end

    test "nearest keeps a hard edge hard" do
      raster = stripes({0, 0, 0, 255}, {255, 255, 255, 255})
      shrunk = Resample.to(raster, {4, 4}, mode: :nearest)

      for <<r, _g, _b, _a <- Raster.to_rgba_binary(shrunk)>>, do: assert(r in [0, 255])
    end
  end

  defp spread(width, height) do
    rgba =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        <<x * 4, y * 4, rem(x + y, 64) * 4, 255>>
      end

    Raster.from_rgba(width, height, rgba)
  end

  defp stripes(left, right) do
    {lr, lg, lb, la} = left
    {rr, rg, rb, ra} = right

    rgba =
      for _y <- 1..8, x <- 0..7, into: <<>> do
        if rem(x, 2) == 0, do: <<lr, lg, lb, la>>, else: <<rr, rg, rb, ra>>
      end

    Raster.from_rgba(8, 8, rgba)
  end
end
