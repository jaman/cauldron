defmodule Cauldron2D.Net.SheetTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Atlas
  alias Cauldron2D.Net.Sheet
  alias FrenchCurve.Raster

  setup do
    atlas =
      Atlas.new(:sheet_test, tile: 4)
      |> Atlas.put(:floor, Raster.new(4, 4, background: {10, 20, 30, 255}))
      |> Atlas.put(:ship, Raster.new(4, 4, background: {200, 0, 0, 255}))
      |> Atlas.put(:wall, Raster.new(4, 4, background: {0, 0, 200, 255}))
      |> Atlas.put({:ship, 1, 16}, Raster.new(4, 4, background: {0, 200, 0, 255}))

    {:ok, atlas: atlas}
  end

  test "every art gets an index and a place on one PNG, the void at index 0", %{atlas: atlas} do
    sheet = Sheet.build(atlas)
    assert sheet.tile == 4
    assert Map.keys(sheet.arts) |> Enum.sort() == [:floor, :ship, :wall, {:ship, 1, 16}]
    assert sheet.arts |> Map.values() |> Enum.sort() == [1, 2, 3, 4]
    assert length(sheet.frames) == 5
    assert Enum.at(sheet.frames, 0) == [0, 0]
    assert <<137, "PNG", _::binary>> = sheet.png
    {w, h} = Sheet.dimensions(sheet)
    assert w * h >= 4 * 16
  end

  test "the index tells a client what each art is, without the pixels", %{atlas: atlas} do
    sheet = Sheet.build(atlas)
    index = Sheet.index(sheet, "/atlas.png")
    assert index.url == "/atlas.png"
    assert index.tile == 4
    assert index.arts["ship"] == sheet.arts[:ship]
    assert index.arts["{:ship, 1, 16}"] == sheet.arts[{:ship, 1, 16}]
    assert index.frames == sheet.frames
    assert index.columns * index.tile == elem(Sheet.dimensions(sheet), 0)
    assert index.anim == %{}
  end

  test "an animated art takes a slot per frame and the index says so" do
    atlas =
      Atlas.new(:sheet_anim_test, tile: 4)
      |> Atlas.put(
        :flame,
        [
          Raster.new(4, 4, background: {255, 0, 0, 255}),
          Raster.new(4, 4, background: {0, 255, 0, 255})
        ],
        fps: 4
      )

    index = atlas |> Sheet.build() |> Sheet.index("/a.png")
    assert index.arts == %{"flame" => 1}
    assert index.anim == %{"1" => %{indices: [1, 2], fps: 4}}
  end

  test "the cached sheet is rebuilt when a different atlas is installed" do
    Atlas.install(Atlas.new(:sheet_cached_test, tile: 4) |> Atlas.put(:a, Raster.new(4, 4)))
    first = Sheet.cached(:sheet_cached_test)
    assert Sheet.cached(:sheet_cached_test) == first

    Atlas.install(
      Atlas.new(:sheet_cached_test, tile: 4)
      |> Atlas.put(:a, Raster.new(4, 4))
      |> Atlas.put(:b, Raster.new(4, 4))
    )

    assert map_size(Sheet.cached(:sheet_cached_test).arts) == 2
  end
end
