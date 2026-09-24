defmodule Cauldron2D.AtlasSolidsTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @tile 4

  defp raster(colour), do: Raster.new(@tile, @tile, background: colour)

  test "an art is flat with its own picture for every face and pose unless told otherwise" do
    atlas = Atlas.new(:solids_plain, tile: @tile) |> Atlas.put(:floor, raster({1, 2, 3, 255}))
    entry = Atlas.entry(atlas, :floor)

    assert entry.height == 0
    assert Atlas.face(atlas, :floor, :top) == entry.sprite
    assert Atlas.face(atlas, :floor, :side) == entry.sprite
    assert Atlas.pose(atlas, :floor, :front, 0) == entry.sprite
    assert Atlas.pose(atlas, :floor, :back, 0) == entry.sprite
  end

  test "a block has a height in storeys and pictures for its top and its sides" do
    atlas =
      Atlas.new(:solids_block, tile: @tile)
      |> Atlas.put(:wall, raster({9, 9, 9, 255}),
        height: 2,
        faces: %{top: raster({1, 1, 1, 255}), side: raster({2, 2, 2, 255})}
      )

    assert Atlas.entry(atlas, :wall).height == 2

    assert Atlas.face(atlas, :wall, :top).raster.rgba ==
             Raster.to_rgba_binary(raster({1, 1, 1, 255}))

    assert Atlas.face(atlas, :wall, :side).raster.rgba ==
             Raster.to_rgba_binary(raster({2, 2, 2, 255}))
  end

  test "a face left out falls back to the art's own picture" do
    atlas =
      Atlas.new(:solids_top_only, tile: @tile)
      |> Atlas.put(:crate, raster({5, 5, 5, 255}),
        height: 1,
        faces: %{top: raster({6, 6, 6, 255})}
      )

    assert Atlas.face(atlas, :crate, :top).raster.rgba ==
             Raster.to_rgba_binary(raster({6, 6, 6, 255}))

    assert Atlas.face(atlas, :crate, :side) == Atlas.entry(atlas, :crate).sprite
  end

  test "a mover has poses, each a run of frames shown at the art's rate" do
    atlas =
      Atlas.new(:solids_poses, tile: @tile)
      |> Atlas.put(:hero, raster({1, 0, 0, 255}),
        fps: 10,
        poses: %{
          back: raster({0, 1, 0, 255}),
          side: [raster({0, 0, 1, 255}), raster({0, 0, 2, 255})]
        }
      )

    assert Atlas.pose(atlas, :hero, :front, 0) == Atlas.entry(atlas, :hero).sprite

    assert Atlas.pose(atlas, :hero, :back, 0).raster.rgba ==
             Raster.to_rgba_binary(raster({0, 1, 0, 255}))

    assert Atlas.pose(atlas, :hero, :side, 0).raster.rgba ==
             Raster.to_rgba_binary(raster({0, 0, 1, 255}))

    assert Atlas.pose(atlas, :hero, :side, 100).raster.rgba ==
             Raster.to_rgba_binary(raster({0, 0, 2, 255}))
  end

  test "a face or pose of the wrong size is refused like any other picture" do
    assert_raise ArgumentError, fn ->
      Atlas.new(:solids_bad, tile: @tile)
      |> Atlas.put(:wall, raster({9, 9, 9, 255}), faces: %{top: Raster.new(2, 2)})
    end
  end

  test "a negative height is refused" do
    assert_raise ArgumentError, fn ->
      Atlas.new(:solids_negative, tile: @tile)
      |> Atlas.put(:hole, raster({0, 0, 0, 255}), height: -1)
    end
  end
end

defmodule Cauldron2D.AtlasSidesTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @tile 4

  defp raster(colour), do: Raster.new(@tile, @tile, background: colour)

  test "a compass side falls back to the side face, then to the art's own picture" do
    atlas =
      Atlas.new(:sides_test, tile: @tile)
      |> Atlas.put(:house, raster({9, 9, 9, 255}),
        height: 1,
        faces: %{side: raster({2, 2, 2, 255}), south: raster({3, 3, 3, 255})}
      )
      |> Atlas.put(:crate, raster({5, 5, 5, 255}), height: 1)

    assert Raster.to_rgba_binary(Atlas.face(atlas, :house, :south).raster) ==
             Raster.to_rgba_binary(raster({3, 3, 3, 255}))

    assert Raster.to_rgba_binary(Atlas.face(atlas, :house, :north).raster) ==
             Raster.to_rgba_binary(raster({2, 2, 2, 255}))

    assert Atlas.face(atlas, :crate, :east) == Atlas.entry(atlas, :crate).sprite
  end
end

defmodule Cauldron2D.AtlasClockTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @tile 4

  defp raster(colour), do: Raster.new(@tile, @tile, background: colour)

  test "frames advance on a clock that reads negative, as a monotonic clock may" do
    atlas =
      Atlas.new(:clock_test, tile: @tile)
      |> Atlas.put(:flame, [raster({1, 0, 0, 255}), raster({2, 0, 0, 255})],
        fps: 10,
        poses: %{side: [raster({3, 0, 0, 255}), raster({4, 0, 0, 255})]}
      )

    assert Atlas.frame_index(atlas, :flame, -576_460_751_840) !=
             Atlas.frame_index(atlas, :flame, -576_460_751_740)

    assert Atlas.pose(atlas, :flame, :side, -1_000) != Atlas.pose(atlas, :flame, :side, -900)
    assert Atlas.frame_index(atlas, :flame, 0) == 0
    assert Atlas.frame_index(atlas, :flame, 100) == 1
  end
end

defmodule Cauldron2D.AtlasSizesTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @tile 4

  defp raster(w, h, colour), do: Raster.new(w, h, background: colour)

  test "an art may be larger than a tile, in any dimension, and says its size" do
    atlas =
      Atlas.new(:sizes_test, tile: @tile)
      |> Atlas.put(:tree, raster(8, 8, {0, 9, 0, 255}))
      |> Atlas.put(:hero, [raster(5, 7, {9, 0, 0, 255}), raster(5, 7, {8, 0, 0, 255})], fps: 4)

    assert Atlas.entry(atlas, :tree).size == {8, 8}
    assert Atlas.entry(atlas, :hero).size == {5, 7}
  end

  test "frames of one art must agree in size, and faces must be a tile" do
    assert_raise ArgumentError, fn ->
      Atlas.new(:sizes_bad, tile: @tile)
      |> Atlas.put(:hero, [raster(5, 7, {9, 0, 0, 255}), raster(4, 4, {8, 0, 0, 255})])
    end

    assert_raise ArgumentError, fn ->
      Atlas.new(:sizes_face, tile: @tile)
      |> Atlas.put(:wall, raster(4, 4, {9, 9, 9, 255}),
        height: 1,
        faces: %{top: raster(8, 8, {1, 1, 1, 255})}
      )
    end
  end

  test "a directory picture larger than a tile loads as one art of its size; a pic's frames are its frames" do
    dir = Path.join(System.tmp_dir!(), "cauldron_sizes_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    rows = fn w, h, key -> String.duplicate(String.duplicate(key, w) <> "\n", h) end
    File.write!(Path.join(dir, "tree.pic"), "T #00ff00\n\n#{rows.(8, 8, "T")}")
    frame = String.trim_trailing(rows.(12, 4, "W"))

    File.write!(
      Path.join(dir, "walk.pic"),
      "W #ff0000\n\n#{frame}\n---\n#{frame}\n---\n#{frame}\n"
    )

    File.write!(Path.join(dir, "dot.pic"), "D #0000ff\n\n#{rows.(2, 2, "D")}")

    assert {:ok, atlas} = Atlas.load(:atlas_sizes_dir, dir, tile: @tile)
    assert Atlas.entry(atlas, :tree).size == {8, 8}
    assert length(Atlas.entry(atlas, :walk).frames) == 3
    assert Atlas.entry(atlas, :walk).size == {12, 4}
    assert Atlas.entry(atlas, :dot).size == {4, 4}
  end
end

defmodule Cauldron2D.AtlasEyeTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @tile 16

  defp atlas do
    Atlas.new(:eye_test, tile: @tile)
    |> Atlas.put(:short, Raster.new(@tile, @tile, background: {250, 250, 20, 255}))
    |> Atlas.put(:tall, Raster.new(@tile, 3 * @tile, background: {20, 20, 250, 255}))
    |> Atlas.put(:giant, Raster.new(@tile, @tile, background: {250, 20, 250, 255}), stand: 4.0)
    |> Atlas.put(:owl, Raster.new(@tile, @tile, background: {200, 200, 200, 255}), eye: 2.5)
  end

  test "an art stands its picture's height over the tile size unless it says otherwise" do
    assert Atlas.standing(atlas(), :short) == 1.0
    assert Atlas.standing(atlas(), :tall) == 3.0
    assert Atlas.standing(atlas(), :giant) == 4.0
  end

  test "an art may name its own eye height, whatever it stands" do
    assert Atlas.eye_height(atlas(), :owl) == 2.5
  end
end
