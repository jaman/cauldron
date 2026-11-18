defmodule Town.LegendTest do
  use ExUnit.Case, async: true

  alias Town.Legend

  @legend """
  PPPPPP
  P.hh.P
  P.hh.P
  P.==.P
  PPPPPP
  """

  test "floors, props and storeys become cells, and a building's door faces the road" do
    town = Legend.build(@legend)

    assert town.size == {6, 5}
    assert town.cells[{1, 1}] == {:grass, [], nil}
    assert town.cells[{0, 0}] == {:grass, [:pine], nil}
    assert town.cells[{2, 3}] == {:road, [], nil}
    assert town.cells[{2, 1}] == {:cobble, [:plaster_ground], nil}
    assert town.cells[{2, 2}] == {:cobble, [:plaster_ground_s], nil}
  end

  test "grass and paving are walkable, buildings, props and water are not" do
    town = Legend.build(@legend)

    assert MapSet.member?(town.walkable, {1, 1})
    assert MapSet.member?(town.walkable, {2, 3})
    refute MapSet.member?(town.walkable, {2, 1})
    refute MapSet.member?(town.walkable, {0, 0})
    assert Enum.sort(town.paved) == [{2, 3}, {3, 3}]
  end

  test "a two-storey building stacks an upper storey on the ground one" do
    town = Legend.build("H=\n")
    assert town.cells[{0, 0}] == {:cobble, [:plaster_ground_e, :plaster_upper], nil}
  end

  test "the town in priv reads and is walkable at the square" do
    Legend.install()
    assert Legend.walkable?({22.5, 21.5})
    assert Legend.cell({-1, -1}) == :void
    assert {48, 48} = Legend.size()
  end
end
