defmodule Cauldron2D.Wx.PainterTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Wx.Painter

  @map %{
    width: 4,
    height: 3,
    tile: 16,
    wrap: false,
    rows: [[1, 0, 0, 1], [0, 2, 0, 0], [1, 0, 0, 1]]
  }

  test "the origin centres the focus, at the map's edge and beyond it, and tiles and movers land in pixels" do
    frame = %{focus: {2.0, 1.5}, movers: [{3, 1.0, 1.0}], hud: [], over: nil}
    blits = Painter.blits(frame, @map, {64, 48}, 16)
    assert Painter.origin(frame, @map, {64, 48}, 16) == {0.0, 0.0}
    assert {1, 0, 0} in blits and {1, 48, 0} in blits and {2, 16, 16} in blits
    assert List.last(blits) == {3, 16, 16}

    far = %{frame | focus: {10.0, 10.0}}
    assert Painter.origin(far, @map, {32, 32}, 16) == {9.0, 9.0}
    assert Painter.blits(far, @map, {32, 32}, 16) == []
    edge = %{frame | focus: {0.0, 0.0}}
    assert Painter.origin(edge, @map, {64, 48}, 16) == {-2.0, -1.5}
    assert {1, 32, 24} in Painter.blits(edge, @map, {64, 48}, 16)
  end

  test "zooming out past a map that does not wrap and back in returns to the focus it left" do
    frame = %{focus: {1.0, 1.0}, movers: [], hud: [], over: nil}
    out = Painter.zoom_about(frame, @map, {64, 48}, 16, 2, {10, 5})
    back = Painter.zoom_about(%{frame | focus: out}, @map, {64, 48}, 2, 16, {10, 5})
    assert_in_delta elem(back, 0), 1.0, 1.0e-9
    assert_in_delta elem(back, 1), 1.0, 1.0e-9
  end

  test "a wrapping map repeats and a mover near an edge is drawn on both sides" do
    map = %{@map | wrap: true}
    frame = %{focus: {0.0, 0.0}, movers: [{3, 3.5, 0.0}], hud: [], over: nil}
    blits = Painter.blits(frame, map, {64, 48}, 16)
    assert {3, 24, 24} in blits
    assert Enum.count(blits, &match?({3, _, _}, &1)) == 1
    assert {1, 16, 8} in blits
  end

  test "a layer of the whole map is every tile once, placed by the focus, with the movers on top" do
    assert {1, 48, 0} in Painter.layer_blits(@map, 16) and
             {2, 16, 16} in Painter.layer_blits(@map, 16)

    assert length(Painter.layer_blits(@map, 16)) == Enum.count(List.flatten(@map.rows), &(&1 > 0))
    frame = %{focus: {2.0, 1.5}, movers: [{3, 1.0, 1.0}], hud: [], over: nil}
    assert [{0, 0}] = Painter.layer_offsets(frame, @map, {64, 48}, 16)
    assert [{3, 16, 16}] = Painter.mover_blits(frame, @map, {64, 48}, 16)
    wrapping = %{@map | wrap: true}
    offsets = Painter.layer_offsets(%{frame | focus: {0.0, 0.0}}, wrapping, {64, 48}, 16)
    assert {-32, -24} in offsets and length(offsets) > 1
  end

  test "a layer can leave indices out, and the cells with those indices in view are blits of their own" do
    layer = Painter.layer_blits(@map, 16, except: MapSet.new([2]))
    refute {2, 16, 16} in layer
    assert {1, 48, 0} in layer
    frame = %{focus: {2.0, 1.5}, movers: [], hud: [], over: nil}
    assert Painter.cell_blits(frame, @map, {64, 48}, 16, MapSet.new([2])) == [{2, 16, 16}]
    assert Painter.cell_blits(frame, @map, {64, 48}, 16, MapSet.new()) == []
  end

  test "a label lands where a mover at its position would" do
    frame = %{
      focus: {2.0, 1.5},
      movers: [],
      labels: [{"a", 1.0, 1.0, "#ffffff", 1}],
      hud: [],
      over: nil
    }

    assert Painter.label_blits(frame, @map, {64, 48}, 16, {1.0, 1.0}) == [{16, 16}]
    assert Painter.label_blits(frame, @map, {64, 48}, 16, {30.0, 30.0}) == []
  end

  test "a canvas point maps back to the world" do
    frame = %{focus: {2.0, 1.5}, movers: [], hud: [], over: nil}
    assert Painter.world_at(frame, @map, {64, 48}, 16, {32, 24}) == {2.0, 1.5}
  end

  test "zooming about a canvas point gives the focus that keeps the world under it there" do
    wrapping = %{@map | wrap: true, width: 40, height: 30}
    frame = %{focus: {20.0, 15.0}, movers: [], hud: [], over: nil}
    point = {10, 5}
    before = Painter.world_at(frame, wrapping, {64, 48}, 16, point)
    focus = Painter.zoom_about(frame, wrapping, {64, 48}, 16, 32, point)
    after_zoom = Painter.world_at(%{frame | focus: focus}, wrapping, {64, 48}, 32, point)
    assert_in_delta elem(before, 0), elem(after_zoom, 0), 1.0e-9
    assert_in_delta elem(before, 1), elem(after_zoom, 1), 1.0e-9
  end
end
