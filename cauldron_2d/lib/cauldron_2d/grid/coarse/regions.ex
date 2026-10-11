defmodule Cauldron2D.Grid.Coarse.Regions do
  @moduledoc """
  The regions of a grid for `Cauldron2D.Grid.Coarse`: within each block of `block` tiles
  a side, the open tiles joined edge to edge, numbered from 1.

  `build/3` returns:

    * `:labels` — a binary of one 32-bit region number for each tile, row by row, 0 for a
      tile that is not open
    * `:count` — how many regions there are
    * `:spots` — a tuple, the region numbered `n` at index `n - 1`, of the region's tile
      nearest its middle
    * `:links` — a tuple in the same order of `[{region, cost}]`, the regions a region
      touches edge to edge across a block border, the cost the distance between spots
    * `:components` — a tuple in the same order of the number shared by every region that
      can reach every other
  """

  alias Cauldron2D.Grid.Coarse.Space

  @type t :: %{
          labels: binary(),
          count: non_neg_integer(),
          spots: tuple(),
          links: tuple(),
          components: tuple()
        }

  @doc "The regions of the tiles `open?` accepts in `space`, in blocks of `block` tiles."
  @spec build(({integer(), integer()} -> boolean()), Space.t(), pos_integer()) :: t()
  def build(open?, space, block) do
    open = open_tiles(open?, space)
    {assigned, count} = label(open, space, block)
    spots = spots(assigned, count)
    links = links(assigned, count, spots, space)

    %{
      labels: encode(assigned, space),
      count: count,
      spots: spots,
      links: links,
      components: components(links, count)
    }
  end

  defp open_tiles(open?, space) do
    for y <- 0..(space.height - 1),
        x <- 0..(space.width - 1),
        open?.({x, y}),
        into: MapSet.new(),
        do: {x, y}
  end

  defp label(open, space, block) do
    for by <- 0..div(space.height - 1, block),
        bx <- 0..div(space.width - 1, block),
        reduce: {%{}, 0} do
      acc -> label_block(acc, block_tiles(open, space, block, {bx, by}))
    end
  end

  defp block_tiles(open, space, block, {bx, by}) do
    for y <- (by * block)..min(by * block + block - 1, space.height - 1),
        x <- (bx * block)..min(bx * block + block - 1, space.width - 1),
        MapSet.member?(open, {x, y}),
        into: MapSet.new(),
        do: {x, y}
  end

  defp label_block(acc, inside) do
    Enum.reduce(inside, acc, fn tile, {assigned, count} = acc ->
      if Map.has_key?(assigned, tile),
        do: acc,
        else: {fill(assigned, inside, [tile], count + 1), count + 1}
    end)
  end

  defp fill(assigned, _inside, [], _region), do: assigned

  defp fill(assigned, inside, [{x, y} = tile | rest], region) do
    if MapSet.member?(inside, tile) and not Map.has_key?(assigned, tile),
      do:
        fill(
          Map.put(assigned, tile, region),
          inside,
          [{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1} | rest],
          region
        ),
      else: fill(assigned, inside, rest, region)
  end

  defp spots(assigned, count) do
    members = Enum.group_by(assigned, fn {_tile, region} -> region end, &elem(&1, 0))

    1..count//1
    |> Enum.map(fn region -> middle(Map.fetch!(members, region)) end)
    |> List.to_tuple()
  end

  defp middle(tiles) do
    size = length(tiles)
    mx = Enum.sum(Enum.map(tiles, &elem(&1, 0))) / size
    my = Enum.sum(Enum.map(tiles, &elem(&1, 1))) / size
    Enum.min_by(tiles, fn {x, y} -> (x - mx) * (x - mx) + (y - my) * (y - my) end)
  end

  defp links(assigned, count, spots, space) do
    touching =
      for {{x, y}, region} <- assigned,
          neighbour <- [{x + 1, y}, {x, y + 1}],
          tile = Space.tile(space, neighbour),
          other = Map.get(assigned, tile),
          other != region,
          reduce: %{} do
        acc ->
          acc
          |> Map.update(region, MapSet.new([other]), &MapSet.put(&1, other))
          |> Map.update(other, MapSet.new([region]), &MapSet.put(&1, region))
      end

    1..count//1
    |> Enum.map(fn region ->
      for other <- Map.get(touching, region, MapSet.new()),
          do: {other, Space.distance(space, spot(spots, region), spot(spots, other))}
    end)
    |> List.to_tuple()
  end

  defp spot(spots, region), do: elem(spots, region - 1)

  defp components(links, count) do
    {numbers, _next} =
      Enum.reduce(1..count//1, {%{}, 1}, fn region, {numbers, next} = acc ->
        if Map.has_key?(numbers, region),
          do: acc,
          else: {spread(numbers, links, [region], next), next + 1}
      end)

    1..count//1 |> Enum.map(&Map.fetch!(numbers, &1)) |> List.to_tuple()
  end

  defp spread(numbers, _links, [], _component), do: numbers

  defp spread(numbers, links, [region | rest], component) do
    if Map.has_key?(numbers, region),
      do: spread(numbers, links, rest, component),
      else:
        spread(
          Map.put(numbers, region, component),
          links,
          Enum.map(elem(links, region - 1), &elem(&1, 0)) ++ rest,
          component
        )
  end

  defp encode(assigned, space) do
    for y <- 0..(space.height - 1),
        x <- 0..(space.width - 1),
        into: <<>>,
        do: <<Map.get(assigned, {x, y}, 0)::32>>
  end
end
