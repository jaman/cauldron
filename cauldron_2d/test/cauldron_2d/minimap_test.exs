defmodule Cauldron2D.MinimapTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Minimap

  @rows [
    "########",
    "#......#",
    "#......#",
    "########"
  ]

  defp solid?({x, y}), do: @rows |> Enum.at(y) |> String.at(x) == "#"

  test "the map is scaled into braille cells, walls in the wall colour, marks over them, empties empty" do
    rows =
      Minimap.rows(
        size: {8, 4},
        solid?: &solid?/1,
        cells: {4, 1},
        marks: [{{3.5, 1.5}, {255, 255, 0}, 2}],
        wall: {0, 0, 255},
        empty: {1, 1, 1}
      )

    assert length(rows) == 1
    [runs] = rows
    assert Enum.map_join(runs, &elem(&1, 0)) |> String.length() == 4
    assert Enum.any?(runs, fn {_text, colour} -> colour == {0, 0, 255} end)
    assert Enum.any?(runs, fn {_text, colour} -> colour == {255, 255, 0} end)

    assert Enum.all?(runs, fn {text, _} ->
             String.to_charlist(text) |> Enum.all?(&(&1 >= 0x2800 and &1 <= 0x28FF))
           end)
  end

  test "the earlier mark wins where two land on one cell, and the walls are kept under a key" do
    rows =
      Minimap.rows(
        size: {8, 4},
        solid?: &solid?/1,
        cells: {2, 1},
        marks: [{{2.0, 1.0}, {255, 0, 0}, 1}, {{2.0, 1.0}, {0, 255, 0}, 1}],
        key: :minimap_test
      )

    assert [[{_, {255, 0, 0}} | _]] = rows

    assert Minimap.rows(
             size: {8, 4},
             solid?: fn _ -> false end,
             cells: {2, 1},
             marks: [],
             key: :minimap_test
           ) ==
             Minimap.rows(
               size: {8, 4},
               solid?: &solid?/1,
               cells: {2, 1},
               marks: [],
               key: :minimap_test
             )
  end

  test "a keyed minimap draws only the cells the marks touch: the same rows as an unkeyed one, in a fraction of the time" do
    width = 120

    solid? = fn {x, y} ->
      x == 0 or y == 0 or x == width - 1 or y == width - 1 or rem(x * 7 + y * 3, 11) == 0
    end

    marks = for n <- 1..20, do: {{rem(n * 37, width) / 1, rem(n * 53, width) / 1}, {255, n, 0}, 2}
    opts = [size: {width, width}, solid?: solid?, cells: {30, 12}, marks: marks]
    plain = Minimap.rows(opts)
    keyed = fn -> Minimap.rows([{:key, :minimap_speed} | opts]) end
    assert keyed.() == plain
    {plain_us, _} = :timer.tc(fn -> for _ <- 1..50, do: Minimap.rows(opts) end)
    {keyed_us, _} = :timer.tc(fn -> for _ <- 1..50, do: keyed.() end)

    assert keyed_us * 4 < plain_us,
           "keyed #{div(keyed_us, 50)} µs against plain #{div(plain_us, 50)} µs a call"

    assert Minimap.rows([{:key, :minimap_speed} | Keyword.put(opts, :marks, [])]) ==
             Minimap.rows(Keyword.put(opts, :marks, []))
  end
end
