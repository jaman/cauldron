defmodule Cauldron2D.Easel.Drafter.ActualSizeTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.{Atlas, Easel}
  alias Cauldron2D.Easel.Drafter.ActualSize

  defp easel do
    Easel.new(4, 2, palette: [{"R", "#ff0000"}], fps: 5)
    |> Easel.paint({0, 0}, "R")
    |> Easel.add_frame()
  end

  test "installs the easel's frames as one square art at the easel's rate" do
    actual = ActualSize.new()
    actual = ActualSize.sync(actual, easel(), %{glyph: "^ ", color: {1, 2, 3}})
    assert Atlas.installed?(actual.name)
    atlas = Atlas.fetch(actual.name)
    assert atlas.tile == 4
    entry = Atlas.entry(atlas, :art)
    assert length(entry.frames) == 2
    assert entry.fps == 5
    assert entry.glyph == "^ "
    assert entry.color == {1, 2, 3}
    assert FrenchCurve.Raster.get_pixel(hd(entry.frames).raster, 0, 0) == {255, 0, 0, 255}
    assert FrenchCurve.Raster.get_pixel(hd(entry.frames).raster, 0, 3) == {0, 0, 0, 0}
  end

  test "sync installs again only when the picture changed" do
    actual = ActualSize.new() |> ActualSize.sync(easel(), %{})
    same = ActualSize.sync(actual, easel(), %{})
    assert same == actual
    changed = ActualSize.sync(actual, Easel.set_fps(easel(), 9), %{})
    assert changed.fingerprint != actual.fingerprint
    assert Atlas.entry(Atlas.fetch(changed.name), :art).fps == 9
  end

  test "the cell function shows the art once, or everywhere when tiled" do
    assert ActualSize.cell(false).({0, 0}) == {:art, [], nil}
    assert ActualSize.cell(false).({1, 0}) == :void
    assert ActualSize.cell(true).({-3, 7}) == {:art, [], nil}
  end
end
