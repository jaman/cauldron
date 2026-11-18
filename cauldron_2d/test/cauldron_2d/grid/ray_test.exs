defmodule Cauldron2D.Grid.RayTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Grid.Ray

  test "a line visits every tile it crosses, in order" do
    tiles = for {tile, _point} <- Ray.tiles({0.5, 0.5}, {2.5, 1.5}), do: tile
    assert tiles == [{0, 0}, {1, 0}, {1, 1}, {2, 1}]
  end

  test "the first solid tile stops the line, at the point it enters" do
    wall = fn {x, _y} -> x == 3 end
    assert {:hit, {3, 0}, {3.0, y}} = Ray.cast({0.5, 0.5}, {6.5, 0.5}, wall)
    assert_in_delta y, 0.5, 1.0e-9
    assert Ray.clear?({0.5, 0.5}, {2.5, 0.5}, wall)
  end

  test "it does not slip between two walls that meet at a corner" do
    corner = fn tile -> tile in [{1, 0}, {0, 1}] end
    refute Ray.clear?({0.5, 0.5}, {1.5, 1.5}, corner)
  end
end
