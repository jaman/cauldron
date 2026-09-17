defmodule Linocut.PicTest do
  use ExUnit.Case, async: true

  alias FrenchCurve.Raster

  @pic """
  R #c33
  W white

  ..RR..
  .RWWR.
  """

  test "a pic is a palette, a blank line, and the picture" do
    assert {:ok, raster} = Linocut.pic(@pic)
    assert Raster.dimensions(raster) == {6, 2}
    assert Raster.get_pixel(raster, 2, 0) == {204, 51, 51, 255}
    assert Raster.get_pixel(raster, 2, 1) == {255, 255, 255, 255}
  end

  test "sprite options apply, so a pic can be centred in a tile" do
    assert {:ok, raster} = Linocut.pic(@pic, size: {8, 4})
    assert Raster.dimensions(raster) == {8, 4}
    assert Raster.get_pixel(raster, 3, 1) == {204, 51, 51, 255}
  end

  test "frames separated by a --- line come back side by side as a strip, or one by one" do
    two = "R #c33\n\nR.\n..\n---\n.R\n..\n"
    assert {:ok, strip} = Linocut.pic(two)
    assert Raster.dimensions(strip) == {4, 2}
    assert Raster.get_pixel(strip, 0, 0) == {204, 51, 51, 255}
    assert Raster.get_pixel(strip, 3, 0) == {204, 51, 51, 255}
    assert {:ok, [first, second]} = Linocut.Pic.frames(two)
    assert Raster.dimensions(first) == {2, 2}
    assert Raster.get_pixel(second, 1, 0) == {204, 51, 51, 255}
    assert {:ok, [_one]} = Linocut.Pic.frames(@pic)
  end

  test "a pic with no blank line, or a colour that does not parse, is an error" do
    assert {:error, :no_picture} = Linocut.pic("R #c33\n..R..\n")
    assert {:error, {:colour, "R", "nope"}} = Linocut.pic("R nope\n\n..R..\n")
  end

  test "load reads a png or a pic by its extension" do
    dir = Path.join(System.tmp_dir!(), "linocut_load_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    {:ok, from_pic} = Linocut.pic(@pic)
    File.write!(Path.join(dir, "ship.pic"), @pic)

    File.write!(
      Path.join(dir, "ship.png"),
      FrenchCurve.Png.encode(6, 2, Raster.to_rgba_binary(from_pic))
    )

    assert {:ok, png} = Linocut.load(Path.join(dir, "ship.png"))
    assert {:ok, pic} = Linocut.load(Path.join(dir, "ship.pic"))
    assert Raster.to_rgba_binary(png) == Raster.to_rgba_binary(pic)
    assert {:error, {:unknown_format, ".txt"}} = Linocut.load(Path.join(dir, "ship.txt"))
    assert {:error, :enoent} = Linocut.load(Path.join(dir, "missing.png"))
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "linocut_load_*"))
  end
end
