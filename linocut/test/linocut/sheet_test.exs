defmodule Linocut.SheetTest do
  @moduledoc """
  Cutting a sprite sheet: how many frames come back, what size they are, and where in each
  frame the drawing sits.
  """

  use ExUnit.Case, async: true

  alias FrenchCurve.Raster
  alias Linocut.Sheet

  describe "cut/2" do
    test "a row of blobs becomes one frame each, all the same size" do
      frames = Sheet.cut(sheet([{2, 4, 6, 10}, {20, 2, 8, 12}, {40, 6, 4, 8}]), gap: 4)

      assert length(frames) == 3
      assert Enum.map(frames, &Raster.dimensions/1) |> Enum.uniq() |> length() == 1
    end

    test "every frame is as tall as the band, so the drawings keep one floor" do
      frames = Sheet.cut(sheet([{2, 4, 6, 10}, {20, 2, 8, 12}]), gap: 4)

      for frame <- frames, do: assert(frame.height == 12)
    end

    test "blobs closer together than the gap are one frame" do
      near = sheet([{2, 2, 6, 8}, {9, 2, 6, 8}])

      assert length(Sheet.cut(near, gap: 4)) == 1
      assert length(Sheet.cut(near, gap: 1)) == 2
    end

    test "the band picks which row of frames is cut" do
      two_rows = sheet([{2, 2, 6, 6}, {20, 2, 6, 6}, {2, 30, 6, 6}])

      assert length(Sheet.cut(two_rows, band: 0, gap: 4)) == 2
      assert length(Sheet.cut(two_rows, band: 1, gap: 4)) == 1
      assert Sheet.cut(two_rows, band: 2, gap: 4) == []
    end

    test "an empty sheet gives no frames" do
      assert Sheet.cut(Raster.new(32, 32)) == []
    end

    test "a frame narrower than the widest is centred in it" do
      [narrow, _wide] = Sheet.cut(sheet([{2, 0, 2, 8}, {20, 0, 8, 8}]), gap: 4)

      assert narrow.width == 8
      assert {_r, _g, _b, 0} = Raster.get_pixel(narrow, 0, 0)
      assert {_r, _g, _b, 255} = Raster.get_pixel(narrow, 3, 0)
    end
  end

  describe "cut_all/2" do
    test "every band's frames come back, top band first" do
      two_rows = sheet([{2, 2, 6, 6}, {20, 2, 6, 6}, {2, 30, 6, 6}])

      assert length(Sheet.cut_all(two_rows, gap: 4)) == 3
    end

    test "frames from different bands are padded to one size" do
      uneven = sheet([{2, 2, 4, 6}, {2, 30, 10, 12}])
      sizes = uneven |> Sheet.cut_all(gap: 4) |> Enum.map(&Raster.dimensions/1)

      assert Enum.uniq(sizes) == [{10, 12}]
    end

    test "a padded frame stands on the bottom of its canvas" do
      uneven = sheet([{2, 2, 4, 4}, {2, 30, 10, 12}])
      [short, _tall] = Sheet.cut_all(uneven, gap: 4)

      assert {_r, _g, _b, 0} = Raster.get_pixel(short, 3, 0)
      assert {_r, _g, _b, 255} = Raster.get_pixel(short, 3, short.height - 1)
    end

    test "an empty sheet gives no frames" do
      assert Sheet.cut_all(Raster.new(32, 32)) == []
    end
  end

  defp sheet(blobs) do
    for {left, top, width, height} <- blobs,
        y <- top..(top + height - 1),
        x <- left..(left + width - 1),
        reduce: Raster.new(64, 48) do
      canvas -> Raster.put_pixel(canvas, x, y, {200, 100, 50, 255})
    end
  end
end
