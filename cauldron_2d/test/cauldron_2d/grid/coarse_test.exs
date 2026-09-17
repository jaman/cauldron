defmodule Cauldron2D.Grid.CoarseTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Grid.Coarse

  @rows [
    "........",
    "........",
    "..####..",
    "..####..",
    "........",
    "........"
  ]

  defp grid({x, y}) when x >= 0 and y >= 0 and x < 8 and y < 6 do
    if @rows |> Enum.at(y) |> String.at(x) == "#", do: :solid, else: :open
  end

  defp grid(_), do: :solid

  test "blocks are passable when every tile in them is open" do
    coarse = Coarse.new(&grid/1, {8, 6}, block: 2)
    assert coarse.width == 4 and coarse.height == 3
    assert Coarse.passable?(coarse, {0.5, 0.5})
    refute Coarse.passable?(coarse, {3.0, 2.5})
    assert Coarse.passable?(coarse, {7.9, 5.9})
  end

  test "a way round the wall as block centres, from and to the nearest passable block" do
    coarse = Coarse.new(&grid/1, {8, 6}, block: 2)
    assert {:ok, path} = Coarse.find(coarse, {0.5, 2.5}, {7.5, 2.5})
    assert List.last(path) == {7.0, 3.0}
    assert Enum.all?(path, fn {x, y} -> Coarse.passable?(coarse, {x, y}) end)
    assert {:ok, out} = Coarse.find(coarse, {3.0, 2.5}, {0.5, 0.5})
    assert List.last(out) == {1.0, 1.0}
  end

  test "the waypoint is the furthest point of the path in a straight clear line" do
    coarse = Coarse.new(&grid/1, {8, 6}, block: 2)
    {:ok, path} = Coarse.find(coarse, {0.5, 0.5}, {7.5, 0.5})
    assert Coarse.waypoint(&grid/1, {0.5, 0.5}, path) == List.last(path)
    {:ok, round} = Coarse.find(coarse, {0.5, 2.5}, {7.5, 2.5})
    assert Coarse.waypoint(&grid/1, {0.5, 2.5}, round) != List.last(round)
  end
end
