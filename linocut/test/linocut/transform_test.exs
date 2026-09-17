defmodule Linocut.TransformTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster

  defp pixel(raster, x, y), do: Raster.get_pixel(raster, x, y)

  @arrow Linocut.sprite(
           """
           R..
           RR.
           R..
           """,
           R: :red
         )

  test "flip mirrors across an axis" do
    horizontal = Linocut.flip(@arrow, :horizontal)
    assert pixel(horizontal, 2, 0) == {255, 0, 0, 255}
    assert pixel(horizontal, 0, 0) == {0, 0, 0, 0}
    assert pixel(horizontal, 1, 1) == {255, 0, 0, 255}

    tall = Linocut.sprite("R\n.\n", R: :red)
    vertical = Linocut.flip(tall, :vertical)
    assert pixel(vertical, 0, 1) == {255, 0, 0, 255}
    assert pixel(vertical, 0, 0) == {0, 0, 0, 0}
  end

  test "rotate turns by quarter turns, counter-clockwise on screen" do
    quarter = Linocut.rotate(@arrow, 90)
    assert Raster.dimensions(quarter) == {3, 3}
    assert pixel(quarter, 0, 2) == {255, 0, 0, 255}
    assert pixel(quarter, 1, 2) == {255, 0, 0, 255}
    assert pixel(quarter, 2, 2) == {255, 0, 0, 255}
    assert pixel(quarter, 1, 1) == {255, 0, 0, 255}
    assert pixel(quarter, 0, 0) == {0, 0, 0, 0}

    half = Linocut.rotate(@arrow, 180)
    assert pixel(half, 2, 0) == {255, 0, 0, 255}
    assert pixel(half, 1, 1) == {255, 0, 0, 255}
    assert pixel(half, 0, 1) == {0, 0, 0, 0}

    assert Linocut.rotate(@arrow, 270) == Linocut.rotate(Linocut.rotate(@arrow, 180), 90)
    assert Linocut.rotate(@arrow, 360) == @arrow

    wide = Linocut.sprite("RR..", R: :red)
    assert Raster.dimensions(Linocut.rotate(wide, 90)) == {1, 4}
  end

  test "transform moves every pixel through a function of its position" do
    moved = Linocut.transform(@arrow, {3, 3}, fn {x, y} -> {x, 2 - y} end)
    assert pixel(moved, 1, 1) == {255, 0, 0, 255}
    assert moved == Linocut.flip(@arrow, :vertical)
  end

  test "frames cuts a strip into tiles of a size, left to right then top to bottom" do
    strip = Linocut.sprite("RG\nBW", R: :red, G: :green, B: :blue, W: :white)
    [a, b, c, d] = Linocut.frames(strip, {1, 1})
    assert pixel(a, 0, 0) == {255, 0, 0, 255}
    assert pixel(b, 0, 0) == {0, 255, 0, 255}
    assert pixel(c, 0, 0) == {0, 0, 255, 255}
    assert pixel(d, 0, 0) == {255, 255, 255, 255}
    assert [_] = Linocut.frames(strip, {2, 2})
  end
end
