defmodule Cauldron2D.SheetTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Atlas, Sheet}
  alias FrenchCurve.Raster

  @tile 4

  defp solid(colour), do: Raster.new(@tile, @tile, background: colour)

  setup do
    atlas =
      Atlas.new(:sheet_core_test, tile: @tile, void: {1, 2, 3})
      |> Atlas.put(:floor, solid({10, 20, 30, 255}))
      |> Atlas.put(:torch, [solid({255, 0, 0, 255}), solid({0, 255, 0, 255})], fps: 5)
      |> Atlas.put(:wall, solid({0, 0, 200, 255}))

    {:ok, atlas: atlas}
  end

  test "every frame of every art gets a slot, index 0 left for nothing", %{atlas: atlas} do
    sheet = Sheet.pack(atlas)
    assert sheet.tile == @tile
    assert sheet.void == {1, 2, 3}
    assert sheet.arts == %{floor: 1, torch: 2, wall: 4}
    assert length(sheet.frames) == 5
    assert sheet.anim == %{2 => %{indices: [2, 3], fps: 5}}
    assert Raster.dimensions(sheet.raster) == {Sheet.columns() * @tile, @tile}
    assert Raster.get_pixel(sheet.raster, 3 * @tile, 0) == {0, 255, 0, 255}
    assert Raster.get_pixel(sheet.raster, 0, 0) == {0, 0, 0, 0}
  end

  test "frames wrap into rows past the column count" do
    atlas =
      Enum.reduce(1..(Sheet.columns() + 2), Atlas.new(:sheet_rows_test, tile: @tile), fn n,
                                                                                         atlas ->
        Atlas.put(atlas, :"a#{n}", solid({n, 0, 0, 255}))
      end)

    sheet = Sheet.pack(atlas)
    assert sheet.rows == 2
    assert Enum.at(sheet.frames, Sheet.columns()) == [0, @tile]
  end

  test "the index showing at a time follows the animation", %{atlas: atlas} do
    sheet = Sheet.pack(atlas)
    assert Sheet.index_at(sheet, 2, 0) == 2
    assert Sheet.index_at(sheet, 2, 200) == 3
    assert Sheet.index_at(sheet, 2, 400) == 2
    assert Sheet.index_at(sheet, 1, 999) == 1
  end

  test "the wire form names arts as strings and carries the animation", %{atlas: atlas} do
    wire = atlas |> Sheet.pack() |> Sheet.index("/atlas.png")
    assert wire.url == "/atlas.png"
    assert wire.arts == %{"floor" => 1, "torch" => 2, "wall" => 4}
    assert wire.anim == %{"2" => %{indices: [2, 3], fps: 5}}
    assert wire.void == "#010203"
    assert wire.columns == Sheet.columns()
  end
end
