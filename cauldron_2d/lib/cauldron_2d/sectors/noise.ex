defmodule Cauldron2D.Sectors.Noise do
  @moduledoc """
  How far a sound carries through a sector map: from the sector it is made in, into every
  sector joined to it by an opening that is not shut.

      index = Cauldron2D.Sectors.Noise.index(map)
      Cauldron2D.Sectors.Noise.spread(world, index, sector)
      #=> %{12 => 0, 13 => 0, 40 => 1}

  The result maps each sector the sound reaches to how many sound-blocking lines it
  crossed on the way there. A sound crosses one line flagged `:blocks_sound` and is
  stopped by a second, so a game can keep a room quiet behind a pair of them. A closed
  door — an opening with no height — stops it entirely.

  `world` is `%{map:, sectors:}`. `index/1` lists each sector's two-sided lines once, to
  pass to every `spread/3`.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap

  @doc "Each sector's two-sided lines, `%{sector => [line_index]}`."
  @spec index(SectorMap.t()) :: %{non_neg_integer() => [non_neg_integer()]}
  def index(%SectorMap{} = map) do
    0..(tuple_size(map.lines) - 1)//1
    |> Enum.filter(&(elem(map.lines, &1).back != nil))
    |> Enum.reduce(%{}, fn line, acc ->
      [0, 1]
      |> Enum.map(&SectorMap.side_sector(map, line, &1))
      |> Enum.uniq()
      |> Enum.reduce(acc, fn sector, inner -> Map.update(inner, sector, [line], &[line | &1]) end)
    end)
  end

  @doc "The sectors a sound made in `sector` reaches. See the moduledoc."
  @spec spread(%{map: SectorMap.t(), sectors: tuple()}, map(), non_neg_integer()) :: %{
          non_neg_integer() => 0 | 1
        }
  def spread(world, index, sector), do: flood(world, index, sector, 0, %{})

  defp flood(world, index, sector, blocks, reached) do
    case Map.get(reached, sector) do
      previous when previous != nil and previous <= blocks ->
        reached

      _unvisited ->
        index
        |> Map.get(sector, [])
        |> Enum.reduce(
          Map.put(reached, sector, blocks),
          &carry(world, index, sector, &1, blocks, &2)
        )
    end
  end

  defp carry(world, index, sector, line_index, blocks, reached) do
    line = elem(world.map.lines, line_index)
    front_sector = SectorMap.side_sector(world.map, line_index, 0)
    back_sector = SectorMap.side_sector(world.map, line_index, 1)
    other = if front_sector == sector, do: back_sector, else: front_sector
    front = elem(world.sectors, front_sector)
    back = elem(world.sectors, back_sector)
    open? = min(front.ceiling, back.ceiling) - max(front.floor, back.floor) > 0

    cond do
      not open? -> reached
      not MapSet.member?(line.flags, :blocks_sound) -> flood(world, index, other, blocks, reached)
      blocks == 0 -> flood(world, index, other, 1, reached)
      true -> reached
    end
  end
end
