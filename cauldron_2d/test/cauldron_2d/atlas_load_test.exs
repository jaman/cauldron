defmodule Cauldron2D.AtlasLoadTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @tile 4

  setup do
    dir = Path.join(System.tmp_dir!(), "cauldron_atlas_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp png(path, raster) do
    {w, h} = Raster.dimensions(raster)
    File.write!(path, FrenchCurve.Png.encode(w, h, Raster.to_rgba_binary(raster)))
  end

  test "every png and pic in the directory becomes an art named by its file", %{dir: dir} do
    png(Path.join(dir, "wall.png"), Raster.new(@tile, @tile, background: {100, 100, 100, 255}))
    File.write!(Path.join(dir, "gem.pic"), "G #00ff00\n\nGGGG\nGGGG\nGGGG\nGGGG\n")

    assert {:ok, atlas} =
             Atlas.load(:atlas_load_dir, dir, tile: @tile, arts: [wall: [glyph: "# "]])

    assert Enum.sort(Atlas.arts(atlas)) == [:gem, :wall]
    assert Atlas.entry(atlas, :wall).glyph == "# "
    assert Atlas.entry(atlas, :wall).color == {100, 100, 100}
    assert Atlas.entry(atlas, :gem).glyph == "GE"
    assert Atlas.entry(atlas, :gem).color == {0, 255, 0}
  end

  test "a picture wider than a tile is a strip of frames", %{dir: dir} do
    strip =
      Raster.new(@tile * 3, @tile)
      |> then(fn r ->
        Enum.reduce(0..(@tile - 1), r, fn y, r ->
          Raster.put_pixel(r, @tile + 1, y, {1, 2, 3, 255})
        end)
      end)

    png(Path.join(dir, "flame.png"), strip)

    assert {:ok, atlas} = Atlas.load(:atlas_load_strip, dir, tile: @tile, fps: 6)
    flame = Atlas.entry(atlas, :flame)
    assert length(flame.frames) == 3
    assert flame.fps == 6
    assert Raster.get_pixel(Enum.at(flame.frames, 1).raster, 1, 0) == {1, 2, 3, 255}
  end

  test "a pic smaller than a tile is centred in it", %{dir: dir} do
    File.write!(Path.join(dir, "dot.pic"), "D white\n\nDD\nDD\n")
    assert {:ok, atlas} = Atlas.load(:atlas_load_small, dir, tile: @tile)
    assert Raster.get_pixel(Atlas.entry(atlas, :dot).sprite.raster, 1, 1) == {255, 255, 255, 255}
    assert Raster.get_pixel(Atlas.entry(atlas, :dot).sprite.raster, 0, 0) == {0, 0, 0, 0}
  end

  test "a file that will not read names itself in the error", %{dir: dir} do
    File.write!(Path.join(dir, "broken.png"), "not a png")

    assert {:error, {:art, "broken.png", :not_png}} =
             Atlas.load(:atlas_load_broken, dir, tile: @tile)

    File.rm!(Path.join(dir, "broken.png"))
    png(Path.join(dir, "odd.png"), Raster.new(@tile + 1, @tile))
    assert {:error, {:art, "odd.png", :size}} = Atlas.load(:atlas_load_odd, dir, tile: @tile)
  end

  test "a missing directory is an error", %{dir: dir} do
    assert {:error, :enoent} =
             Atlas.load(:atlas_load_missing, Path.join(dir, "nope"), tile: @tile)
  end
end

defmodule Cauldron2D.AtlasLoadDeriveTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  setup do
    dir =
      Path.join(System.tmp_dir!(), "cauldron_atlas_derive_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "knight.pic"),
      "H #a05000\nC #2040c0\nS #ffd0a0\n\n.HH.\nSS..\nCCCC\nC..C\n"
    )

    File.write!(Path.join(dir, "hat.pic"), "B #000000\n\nBBBB\n....\n....\n....\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "derived arts in the manifest are built from the pictures, and from each other", %{
    dir: dir
  } do
    File.write!(
      Path.join(dir, "atlas.txt"),
      "knight_red\tR \t#c02020\t\tfrom knight; colour C #c02020\nknight_red_hat\t\t\t\tfrom knight_red; over hat\nknight_left\t\t\t\tfrom knight; flip h\n"
    )

    assert {:ok, atlas} = Atlas.load(:atlas_derived, dir, tile: 4)

    assert Enum.sort(Atlas.arts(atlas)) == [
             :hat,
             :knight,
             :knight_left,
             :knight_red,
             :knight_red_hat
           ]

    red = Atlas.entry(atlas, :knight_red)
    assert red.glyph == "R "
    assert Raster.get_pixel(hd(red.frames).raster, 0, 2) == {192, 32, 32, 255}

    assert Raster.get_pixel(hd(Atlas.entry(atlas, :knight).frames).raster, 0, 2) ==
             {32, 64, 192, 255}

    hatted = hd(Atlas.entry(atlas, :knight_red_hat).frames).raster
    assert Raster.get_pixel(hatted, 0, 0) == {0, 0, 0, 255}
    assert Raster.get_pixel(hatted, 0, 2) == {192, 32, 32, 255}

    left = hd(Atlas.entry(atlas, :knight_left).frames).raster

    assert Raster.get_pixel(left, 3, 1) ==
             Raster.get_pixel(hd(Atlas.entry(atlas, :knight).frames).raster, 0, 1)
  end

  test "a derivation that cannot be made names the art", %{dir: dir} do
    File.write!(Path.join(dir, "atlas.txt"), "ghost_hat\t\t\t\tfrom ghost; over hat\n")
    assert {:error, {:art, :ghost_hat, message}} = Atlas.load(:atlas_derived_bad, dir, tile: 4)
    assert message =~ "ghost"

    File.write!(
      Path.join(dir, "atlas.txt"),
      "loop_a\t\t\t\tfrom loop_b\nloop_b\t\t\t\tfrom loop_a\n"
    )

    assert {:error, {:art, name, message}} = Atlas.load(:atlas_derived_loop, dir, tile: 4)
    assert name in [:loop_a, :loop_b]
    assert message =~ "loop"
  end
end
