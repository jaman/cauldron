defmodule Linocut.FontTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster
  alias Linocut.Font

  test "text renders three by five glyphs with a pixel between, in the colour" do
    raster = Font.render("AB", :white)
    assert Raster.dimensions(raster) == {7, 5}
    assert Raster.get_pixel(raster, 1, 0) == {255, 255, 255, 255}
    assert Raster.get_pixel(raster, 3, 0) == {0, 0, 0, 0}
    assert Font.width("AB") == 7
    assert Font.width("") == 0
    assert Raster.dimensions(Font.render("", :white)) == {1, 5}
  end

  test "lowercase draws as capitals, unknown characters as a box, and a scale enlarges" do
    assert Raster.to_rgba_binary(Font.render("abc", :red)) ==
             Raster.to_rgba_binary(Font.render("ABC", :red))

    box = Font.render("é", :red)
    assert Raster.get_pixel(box, 0, 0) == {255, 0, 0, 255}
    assert Raster.get_pixel(box, 1, 1) == {0, 0, 0, 0}
    assert Raster.dimensions(Font.render("A", :red, scale: 2)) == {6, 10}
  end

  test "every printable ascii character has a glyph" do
    for code <- ?!..?~,
        do:
          assert(Font.glyph(<<code::utf8>>) != Font.glyph("é"), "no glyph for #{<<code::utf8>>}")

    assert Font.glyph(" ") == ["...", "...", "...", "...", "..."]
  end
end
