defmodule Cauldron2D.Grid.PathTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Grid.Path

  @rows [
    "......",
    ".####.",
    ".#....",
    ".#.##.",
    "......"
  ]

  defp passable?({x, y}) when x >= 0 and y >= 0 and x < 6 and y < 5,
    do: @rows |> Enum.at(y) |> String.at(x) == "."

  defp passable?(_), do: false

  test "breadth-first finds a shortest way, goal last, start left out" do
    assert {:ok, path} = Path.find(&passable?/1, {0, 0}, {5, 2}, size: {6, 5})
    assert List.last(path) == {5, 2}
    assert hd(path) != {0, 0}
    assert length(path) == 7
    assert Enum.all?(path, &passable?/1)
  end

  test "no way is :none, and the same cell is an empty path" do
    walled = fn {x, y} -> passable?({x, y}) and {x, y} not in [{5, 1}, {2, 2}, {5, 3}] end
    assert :none = Path.find(walled, {0, 0}, {3, 2}, size: {6, 5})
    assert {:ok, []} = Path.find(&passable?/1, {1, 0}, {1, 0}, size: {6, 5})
  end

  test "a wrapping grid goes round the edge, and eight neighbours cut corners" do
    assert {:ok, path} = Path.find(&passable?/1, {0, 0}, {5, 0}, size: {6, 5}, wrap?: true)
    assert path == [{5, 0}]

    assert {:ok, diagonal} =
             Path.find(&passable?/1, {0, 0}, {1, 4}, size: {6, 5}, neighbours: :eight)

    assert length(diagonal) == 4
  end

  test "the search gives up past its limit" do
    assert :none = Path.find(&passable?/1, {0, 0}, {5, 4}, size: {6, 5}, limit: 3)
  end

  test "A* finds the same length as breadth-first, and honours a cost" do
    {:ok, bfs} = Path.find(&passable?/1, {0, 0}, {5, 2}, size: {6, 5})
    {:ok, astar} = Path.astar(&passable?/1, {0, 0}, {5, 2}, size: {6, 5})
    assert length(astar) == length(bfs)
    assert List.last(astar) == {5, 2}

    mud = fn {_x, y} -> if y == 0, do: 10.0, else: 1.0 end
    {:ok, cheap} = Path.astar(&passable?/1, {0, 0}, {5, 4}, size: {6, 5}, cost: mud)
    refute Enum.any?(cheap, fn {_x, y} -> y == 0 end)
  end
end
