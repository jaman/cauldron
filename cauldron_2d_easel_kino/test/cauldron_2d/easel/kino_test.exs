defmodule Cauldron2D.Easel.KinoTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.Kino, as: EaselKino
  alias FrenchCurve.Raster

  @pic "R #c33\n\nR.\n.R\n---\n.R\nR.\n"

  setup_all do
    dir = Path.join(System.tmp_dir!(), "easel_kino_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "flame.pic"), @pic)
    File.write!(Path.join(dir, "wall.pic"), "W white\n\nWW\nWW\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp size(png) do
    {:ok, raster} = Linocut.Png.decode(png)
    Raster.dimensions(raster)
  end

  test "a picture becomes a scaled png image; an easel's frames sit side by side", %{dir: dir} do
    {:ok, easel} = Easel.from_pic(@pic)
    image = EaselKino.image(easel, scale: 3)
    assert %Kino.Image{mime_type: "image/png"} = image
    assert size(image.content) == {12, 6}
    assert size(EaselKino.png(Path.join(dir, "wall.pic"), scale: 2)) == {4, 4}
    assert size(EaselKino.png(Raster.new(5, 1), scale: 1)) == {5, 1}
  end

  test "a directory becomes its sheet", %{dir: dir} do
    image = EaselKino.sheet(dir, tile: 2, scale: 1)
    assert size(image.content) == {32, 2}
  end

  test "an animation is one image for one frame and a Kino.animate for more", %{dir: dir} do
    assert %Kino.Image{} = EaselKino.animate(Path.join(dir, "wall.pic"))
    {:ok, easel} = Easel.from_pic(@pic)
    assert %Kino.Frame{} = EaselKino.animate(easel, fps: 20)
  end
end
