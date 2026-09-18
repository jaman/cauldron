defmodule Cauldron2D.Drafter.Surface.ScaleTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Drafter.Surface.Scale

  describe "how many pixels a tile gets" do
    test "a whole number of times the tile, nearest to a row of cells" do
      assert %Scale{factor: {:magnify, 2}, pixels: 32} = Scale.new({14, 30}, 16, 1)
      assert %Scale{factor: {:magnify, 1}, pixels: 16} = Scale.new({10, 20}, 16, 1)
      assert %Scale{factor: {:magnify, 3}, pixels: 24} = Scale.new({10, 20}, 8, 1)
    end

    test "zoom multiplies the size wanted before it is rounded" do
      assert %Scale{factor: {:magnify, 4}, pixels: 64} = Scale.new({14, 30}, 16, 2)
      assert %Scale{factor: {:magnify, 1}, pixels: 16} = Scale.new({14, 30}, 16, 0.5)
    end

    test "below half a tile the tile is shrunk by a divisor of its size" do
      assert %Scale{factor: {:reduce, 2}, pixels: 8} = Scale.new({14, 30}, 16, 0.25)
      assert %Scale{factor: {:reduce, 4}, pixels: 4} = Scale.new({14, 30}, 16, 0.125)
      assert %Scale{factor: {:reduce, 4}, pixels: 3} = Scale.new({10, 20}, 12, 0.125)
    end

    test "never less than a pixel a tile" do
      assert %Scale{factor: {:reduce, 8}, pixels: 1} = Scale.new({10, 20}, 8, 0.001)
    end
  end

  describe "the pane" do
    setup do
      {:ok, scale: Scale.new({8, 16}, 8, 1), rect: %{x: 3, y: 2, width: 20, height: 10}}
    end

    test "is measured in pixels from the cell size", %{scale: scale, rect: rect} do
      assert Scale.pane(scale, rect) == {160, 160}
    end

    test "holds a fractional number of tiles", %{scale: scale, rect: rect} do
      assert Scale.tiles(scale, rect) == {10.0, 10.0}
      assert Scale.tiles(scale, %{rect | width: 21, height: 9}) == {10.5, 9.0}
    end

    test "a point in tiles lands on a cell and a pixel offset inside it", %{scale: scale} do
      assert Scale.place(scale, {5.25, 5.5}) == {10, 5, 4, 8}
      assert Scale.place(scale, {0.0, 0.0}) == {0, 0, 0, 0}
      assert Scale.place(scale, {-0.1, 2.0}) == {-1, 2, 6, 0}
    end

    test "a fraction of a tile scrolls by whole drawn pixels", %{scale: scale} do
      assert Scale.scroll(scale, {0.3, 0.2}) == {5, 3}
    end
  end
end
