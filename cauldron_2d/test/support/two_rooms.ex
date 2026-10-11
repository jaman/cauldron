defmodule Cauldron2D.Test.TwoRooms do
  @moduledoc """
  A sector map for tests: room A (`x` 0–256) and room B (`x` 288–544), both `y` 0–256,
  joined by a doorway sector (`x` 256–288, `y` 96–160). Floors are at 0 and ceilings at
  128; `door/2` sets the doorway's floor and ceiling.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap

  @doc "The map with its BSP built."
  @spec map() :: SectorMap.t()
  def map do
    vertices = {
      {0.0, 0.0},
      {0.0, 256.0},
      {256.0, 256.0},
      {256.0, 160.0},
      {256.0, 96.0},
      {256.0, 0.0},
      {288.0, 160.0},
      {288.0, 96.0},
      {288.0, 256.0},
      {544.0, 256.0},
      {544.0, 0.0},
      {288.0, 0.0}
    }

    walls = [
      {0, 1, 0},
      {1, 2, 0},
      {2, 3, 0},
      {4, 5, 0},
      {5, 0, 0},
      {3, 6, 1},
      {7, 4, 1},
      {6, 8, 2},
      {8, 9, 2},
      {9, 10, 2},
      {10, 11, 2},
      {11, 7, 2}
    ]

    openings = [{3, 4, 0, 1}, {7, 6, 2, 1}]

    {lines, sides} =
      Enum.reduce(walls, {[], []}, fn {from, to, sector}, {lines, sides} ->
        {[line(from, to, length(sides), nil) | lines], [side(sector, 1) | sides]}
      end)

    {lines, sides} =
      Enum.reduce(openings, {lines, sides}, fn {from, to, front, back}, {lines, sides} ->
        front_index = length(sides)

        {[line(from, to, front_index, front_index + 1) | lines],
         [side(back, nil), side(front, nil) | sides]}
      end)

    sector = %{
      floor: 0.0,
      ceiling: 128.0,
      floor_picture: 0,
      ceiling_picture: 0,
      light: 160,
      special: 0,
      tag: 0
    }

    SectorMap.with_bsp(%SectorMap{
      vertices: vertices,
      lines: lines |> Enum.reverse() |> List.to_tuple(),
      sides: sides |> Enum.reverse() |> List.to_tuple(),
      sectors: {sector, sector, sector}
    })
  end

  @doc "The map's sectors with the doorway's floor and ceiling at the heights given."
  @spec door(SectorMap.t(), {number(), number()}) :: tuple()
  def door(map, {floor, ceiling}),
    do: put_elem(map.sectors, 1, %{elem(map.sectors, 1) | floor: floor, ceiling: ceiling})

  defp line(from, to, front, back),
    do: %{from: from, to: to, front: front, back: back, flags: MapSet.new(), special: 0, tag: 0}

  defp side(sector, middle),
    do: %{sector: sector, x_offset: 0.0, y_offset: 0.0, upper: nil, middle: middle, lower: nil}
end
