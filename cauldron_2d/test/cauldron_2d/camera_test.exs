defmodule Cauldron2D.CameraTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Camera

  defp marker, do: fn {x, y} -> {:tile, [], {x, y}} end

  defp view(opts), do: Camera.view(Keyword.merge([size: {4, 3}, cell: marker()], opts))

  test "is the size it was asked for" do
    camera = view(focus: {10, 10}, size: {13, 9})

    assert camera.columns == 13
    assert camera.rows == 9
    assert length(camera.cells) == 9
    assert Enum.all?(camera.cells, &(length(&1) == 13))
  end

  test "centres on the focus when the world has no edges" do
    camera = view(focus: {100, 100}, size: {4, 3})

    assert camera.origin == {98, 99}
    assert camera.cells |> hd() |> hd() == {:tile, [], {98, 99}}
  end

  test "clamps to the world rather than panning past its edge" do
    assert view(focus: {0, 0}, bounds: {20, 20}).origin == {0, 0}
    assert view(focus: {19, 19}, bounds: {20, 20}).origin == {16, 17}
  end

  test "centres a world smaller than the viewport instead of clamping it to a corner" do
    camera = view(focus: {1, 1}, size: {10, 6}, bounds: {4, 2})

    assert camera.origin == {-3, -2}
  end

  test "asks the world for every visible coordinate, once" do
    {:ok, seen} = Agent.start_link(fn -> [] end)

    Camera.view(
      focus: {5, 5},
      size: {3, 2},
      cell: fn point ->
        Agent.update(seen, &[point | &1])
        :void
      end
    )

    points = Agent.get(seen, & &1)

    assert length(points) == 6
    assert length(Enum.uniq(points)) == 6
    assert {4, 4} in points
  end

  describe "mapping a screen position back to the world" do
    test "origin/3 agrees with what view/1 drew" do
      camera = view(focus: {19, 19}, bounds: {20, 20})

      assert Camera.origin({19, 19}, {4, 3}, {20, 20}) == camera.origin
    end

    test "a cell resolves to the tile it is in, at that cell's centre" do
      assert Camera.tile_at({0, 0}, {0, 0}) == {0.25, 0.5}
      assert Camera.tile_at({0, 0}, {1, 0}) == {0.75, 0.5}
      assert Camera.tile_at({0, 0}, {2, 0}) == {1.25, 0.5}

      for column <- 0..7 do
        {x, _y} = Camera.tile_at({0, 0}, {column, 0})
        assert trunc(x) == div(column, 2)
      end
    end

    test "is offset by the camera's origin" do
      assert Camera.tile_at({10, 4}, {6, 2}) == {13.25, 6.5}
    end
  end

  describe "tiles are two cells wide and one tall" do
    test "so square art stays square on a screen whose cells are not" do
      assert Camera.columns_for(80) == 40
      assert Camera.rows_for(24) == 24
    end

    test "and a pane too small for a tile still gets one" do
      assert Camera.columns_for(1) == 1
      assert Camera.columns_for(0) == 1
      assert Camera.rows_for(0) == 1
    end
  end

  describe "scrolling by fractions of a tile" do
    test "the exact origin puts the focus at the centre of the viewport" do
      assert Camera.exact_origin({100.0, 100.0}, {4, 3}, :unbounded) == {98.0, 98.5}
      assert Camera.exact_origin({0.25, 0.0}, {4, 3}, {20, 20}) == {0.0, 0.0}
      assert Camera.exact_origin({19.9, 19.0}, {4, 3}, {20, 20}) == {16.0, 17.0}
    end

    test "a scrolled view reads one more column and row and reports the fraction to shift by" do
      camera = view(focus: {100.25, 100.0}, size: {4, 3}, scroll: true)

      assert camera.origin == {98, 98}
      assert camera.scroll == {0.25, 0.5}
      assert camera.columns == 4
      assert camera.rows == 3
      assert length(camera.cells) == 4
      assert Enum.all?(camera.cells, &(length(&1) == 5))
      assert camera.cells |> hd() |> hd() == {:tile, [], {98, 98}}
    end

    test "an unscrolled view has no fraction" do
      assert view(focus: {100.25, 100.0}).scroll == {0.0, 0.0}
    end
  end

  describe "zoom" do
    test "a zoomed size is the pane's tiles over the zoom, kept exact" do
      assert Camera.zoomed({40, 30}, 1) == {40.0, 30.0}
      assert Camera.zoomed({40, 30}, 2) == {20.0, 15.0}
      assert Camera.zoomed({41, 30}, 2) == {20.5, 15.0}
      assert Camera.zoomed({40, 30}, 0.25) == {160.0, 120.0}
    end

    test "a fractional size centres the focus exactly and reads whole tiles to cover it" do
      camera = view(focus: {100.0, 100.0}, size: {20.5, 15.0}, scroll: true)
      assert camera.origin == {89, 92}
      assert camera.scroll == {0.75, 0.5}
      assert camera.columns == 21
      assert camera.rows == 15
      assert Enum.all?(camera.cells, &(length(&1) == 22))
    end

    test "a cell resolves to a tile through the zoom: twice as many cells to a tile at 2, half at 0.5" do
      assert Camera.tile_at({10.0, 10.0}, {0, 0}, 2) == {10.125, 10.25}
      assert Camera.tile_at({10.0, 10.0}, {3, 1}, 2) == {10.875, 10.75}
      assert Camera.tile_at({10.0, 10.0}, {0, 0}, 0.5) == {10.5, 11.0}
      assert Camera.tile_at({10.0, 10.0}, {0, 0}, 1) == Camera.tile_at({10.0, 10.0}, {0, 0})
    end

    test "zooming about a point keeps the world under it where it is on screen" do
      size = {40, 30}
      focus = {100.0, 100.0}
      cell = {10, 5}

      before =
        Camera.tile_at(Camera.exact_origin(focus, Camera.zoomed(size, 1), :unbounded), cell, 1)

      focus = Camera.zoom_about(focus, cell, size, 1, 2, :unbounded)

      after_zoom =
        Camera.tile_at(Camera.exact_origin(focus, Camera.zoomed(size, 2), :unbounded), cell, 2)

      assert_in_delta elem(before, 0), elem(after_zoom, 0), 1.0e-9
      assert_in_delta elem(before, 1), elem(after_zoom, 1), 1.0e-9
    end

    test "zooming about a point in a bounded world lands on a focus the clamp allows" do
      focus = Camera.zoom_about({2.0, 2.0}, {0, 0}, {40, 30}, 1, 0.5, {60, 60})

      assert Camera.exact_origin(focus, Camera.zoomed({40, 30}, 0.5), {60, 60}) == {-10.0, -0.0} or
               Camera.exact_origin(focus, Camera.zoomed({40, 30}, 0.5), {60, 60}) == {-10.0, 0.0}
    end
  end
end
