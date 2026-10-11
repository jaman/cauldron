defmodule Cauldron2D.Grid.CoarseTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Collision
  alias Cauldron2D.Grid.Coarse

  defp grid_of(rows) do
    cells =
      for {row, y} <- Enum.with_index(rows),
          {char, x} <- Enum.with_index(String.graphemes(row)),
          into: %{},
          do: {{x, y}, if(char == "#", do: :solid, else: :open)}

    fn cell -> Map.get(cells, cell, :solid) end
  end

  defp size(rows), do: {String.length(hd(rows)), length(rows)}

  defp walkable?(grid, from, path) do
    [from | path]
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> match?({:clear, _}, Collision.sweep(grid, a, b, 0.0)) end)
  end

  test "a way down a corridor one tile wide, off the block lines" do
    rows = [
      "##########",
      "#...######",
      "###.######",
      "###.######",
      "###.######",
      "###.######",
      "###.######",
      "###.######",
      "###.######",
      "###.....##",
      "##########"
    ]

    grid = grid_of(rows)
    coarse = Coarse.new(grid, size(rows), block: 4)
    assert {:ok, path} = Coarse.find(coarse, {1.5, 1.5}, {7.5, 9.5}, ahead: 10)
    assert List.last(path) == {7.5, 9.5}
    assert walkable?(grid, {1.5, 1.5}, path)
  end

  test "a way the length of a grid far larger than a block search would cover" do
    rows =
      for y <- 0..199 do
        for x <- 0..199, into: "" do
          cond do
            rem(y, 20) == 10 and x != 0 and x != 199 and rem(div(y, 20), 2) == 0 -> "#"
            rem(y, 20) == 10 and x != 0 and x != 199 and x > 1 -> "#"
            true -> "."
          end
        end
      end

    grid = grid_of(rows)
    coarse = Coarse.new(grid, size(rows))
    assert Coarse.reachable?(coarse, {100.5, 0.5}, {100.5, 199.5})
    assert {:ok, path} = Coarse.find(coarse, {100.5, 0.5}, {100.5, 199.5})
    assert walkable?(grid, {100.5, 0.5}, path)
  end

  test "a start beside a wall is never taken from the far side of it" do
    rows = [
      "..#.....",
      "..#.....",
      "..#.....",
      "..#.....",
      "........"
    ]

    grid = grid_of(rows)
    coarse = Coarse.new(grid, size(rows), block: 2)
    assert {:ok, path} = Coarse.find(coarse, {1.9, 0.5}, {3.5, 0.5})
    assert walkable?(grid, {1.9, 0.5}, path)
    assert Enum.any?(path, fn {_x, y} -> y > 4 end)
  end

  test "on a wrapping grid the way crosses the edge without jumping" do
    rows = [
      "....#....#....",
      "....#....#....",
      "....#....#...."
    ]

    grid = fn {x, y} -> grid_of(rows).({Integer.mod(x, 14), Integer.mod(y, 3)}) end
    coarse = Coarse.new(grid, size(rows), wrap?: true, block: 4)
    assert {:ok, path} = Coarse.find(coarse, {12.5, 1.5}, {1.5, 1.5})
    assert List.last(path) == {15.5, 1.5}
    assert walkable?(grid, {12.5, 1.5}, path)
  end

  test "no way between parts no opening joins" do
    rows = [
      "...#...",
      "...#...",
      "...#..."
    ]

    coarse = Coarse.new(grid_of(rows), size(rows))
    refute Coarse.reachable?(coarse, {0.5, 0.5}, {6.5, 0.5})
    assert Coarse.find(coarse, {0.5, 0.5}, {6.5, 0.5}) == :none
  end

  test "the waypoint is the last point a body of the radius reaches in a clear straight line" do
    rows = [
      "........",
      "........",
      "..####..",
      "..####..",
      "........",
      "........"
    ]

    grid = grid_of(rows)
    coarse = Coarse.new(grid, size(rows), block: 2)
    {:ok, straight} = Coarse.find(coarse, {0.5, 0.5}, {7.5, 0.5})
    assert Coarse.waypoint(grid, {0.5, 0.5}, straight, 0.45) == {7.5, 0.5}

    {:ok, round} = Coarse.find(coarse, {1.5, 2.5}, {7.5, 2.5})
    point = Coarse.waypoint(grid, {1.5, 2.5}, round, 0.45)
    assert point != List.last(round)
    assert match?({:clear, _}, Collision.sweep(grid, {1.5, 2.5}, point, 0.45))
  end
end
