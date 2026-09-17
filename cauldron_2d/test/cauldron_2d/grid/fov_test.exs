defmodule Cauldron2D.Grid.FovTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Grid.Fov

  @rows [
    ".......",
    "...#...",
    ".......",
    ".......",
    "......."
  ]

  defp transparent?({x, y}) when x >= 0 and y >= 0 and x < 7 and y < 5,
    do: @rows |> Enum.at(y) |> String.at(x) == "."

  defp transparent?(_), do: false

  test "the origin is always seen, the wall is seen, and what is behind the wall is not" do
    seen = Fov.compute(&transparent?/1, {3, 3}, 6)
    assert MapSet.member?(seen, {3, 3})
    assert MapSet.member?(seen, {3, 1})
    refute MapSet.member?(seen, {3, 0})
    assert MapSet.member?(seen, {0, 0})
  end

  test "nothing beyond the radius is seen, and sight is mutual" do
    assert Fov.compute(&transparent?/1, {0, 0}, 1) |> MapSet.member?({2, 0}) == false
    a = Fov.compute(&transparent?/1, {0, 4}, 8)
    b = Fov.compute(&transparent?/1, {6, 0}, 8)
    assert MapSet.member?(a, {6, 0}) == MapSet.member?(b, {0, 4})
  end

  test "walled in, only the walls are seen" do
    boxed = fn {x, y} -> {x, y} == {1, 1} end
    seen = Fov.compute(boxed, {1, 1}, 5)
    assert MapSet.member?(seen, {1, 1})
    assert MapSet.member?(seen, {0, 0}) and MapSet.member?(seen, {2, 2})
    refute MapSet.member?(seen, {3, 1})
  end
end
