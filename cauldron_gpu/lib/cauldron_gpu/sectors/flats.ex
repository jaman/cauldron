if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Flats do
    @moduledoc """
    Floors and ceilings of a sector map as `CauldronGPU.Sectors.Surfaces` surfaces.

    Each subsector of the map's BSP becomes one convex polygon: the map's bounds cut by
    every partition line above it, then by each of its own segs. The polygons cover every
    sector, concave or holed, without gaps. Floors face up, ceilings down; both are
    textured in map space, one picture's width and height a repeat, and keyed
    `{:picture, id}`. Sectors whose ceiling (or floor) picture is in `sky` get no ceiling
    (or floor).

        CauldronGPU.Sectors.Flats.surfaces(map, pictures, MapSet.new([sky_flat]))
    """

    alias Cauldron2D.Sectors.{Bsp, Pictures}
    alias Cauldron2D.Sectors.Map, as: SectorMap
    alias CauldronGPU.Sectors.Surfaces

    @tolerance 1.0e-3

    @type polygon :: [SectorMap.point()]

    @doc "The floor and ceiling surfaces of every subsector of `map`, which must carry a BSP."
    @spec surfaces(SectorMap.t(), Pictures.t(), MapSet.t()) :: [Surfaces.surface()]
    def surfaces(%SectorMap{} = map, %Pictures{} = pictures, sky) do
      map
      |> polygons()
      |> Enum.flat_map(fn {sector, points} ->
        planes(elem(map.sectors, sector), points, pictures, sky)
      end)
    end

    @doc "Each subsector's convex polygon, counter-clockwise, as `{sector, points}`."
    @spec polygons(SectorMap.t()) :: [{non_neg_integer(), polygon()}]
    def polygons(%SectorMap{} = map), do: descend(map, Bsp.root(map), bounds(map), [])

    defp descend(_map, _child, polygon, acc) when length(polygon) < 3, do: acc

    defp descend(map, {:leaf, index}, polygon, acc) do
      subsector = elem(map.subsectors, index)

      subsector.first
      |> Range.new(subsector.first + subsector.count - 1, 1)
      |> Enum.map(&elem(map.segs, &1))
      |> Enum.reduce(polygon, fn seg, points -> clip(points, seg_line(seg), :right) end)
      |> tidy()
      |> then(&leaf(subsector.sector, &1, acc))
    end

    defp descend(map, {:node, index}, polygon, acc) do
      node = elem(map.nodes, index)
      line = {node.x, node.y, node.dx, node.dy}
      {right, left} = node.children
      acc = descend(map, right, clip(polygon, line, :right), acc)
      descend(map, left, clip(polygon, line, :left), acc)
    end

    defp leaf(sector, points, acc) when length(points) >= 3, do: [{sector, points} | acc]
    defp leaf(_sector, _points, acc), do: acc

    defp seg_line(%{from: {x, y}, to: {tx, ty}}), do: {x, y, tx - x, ty - y}

    defp bounds(%SectorMap{vertices: vertices}) do
      {xs, ys} = vertices |> Tuple.to_list() |> Enum.unzip()
      {left, right} = Enum.min_max(xs)
      {bottom, top} = Enum.min_max(ys)
      margin = 64.0

      [
        {left - margin, bottom - margin},
        {right + margin, bottom - margin},
        {right + margin, top + margin},
        {left - margin, top + margin}
      ]
    end

    defp clip(points, line, side) when length(points) >= 3 do
      measured = Enum.map(points, &{&1, outside(&1, line, side)})

      measured
      |> Enum.zip(tl(measured) ++ [hd(measured)])
      |> Enum.flat_map(&edge/1)
    end

    defp clip(_points, _line, _side), do: []

    defp outside({px, py}, {x, y, dx, dy}, side) do
      length = :math.sqrt(dx * dx + dy * dy)
      across = ((py - y) * dx - dy * (px - x)) / max(length, 1.0e-9)
      if(side == :right, do: across, else: -across) - @tolerance
    end

    defp edge({{_a, inside_a}, {b, inside_b}}) when inside_a <= 0 and inside_b <= 0, do: [b]
    defp edge({{a, da}, {b, db}}) when da <= 0, do: [crossing(a, b, da, db)]
    defp edge({{a, da}, {b, db}}) when db <= 0, do: [crossing(a, b, da, db), b]
    defp edge(_outside), do: []

    defp crossing({ax, ay}, {bx, by}, da, db) do
      t = da / (da - db)
      {ax + (bx - ax) * t, ay + (by - ay) * t}
    end

    defp tidy(points) do
      points
      |> Enum.chunk_by(&rounded/1)
      |> Enum.map(&hd/1)
      |> drop_closing()
      |> then(fn kept -> if area(kept) > @tolerance, do: kept, else: [] end)
    end

    defp rounded({x, y}), do: {Float.round(x * 1.0, 3), Float.round(y * 1.0, 3)}

    defp drop_closing([first | _] = points) when length(points) > 1 do
      if rounded(first) == rounded(List.last(points)), do: Enum.drop(points, -1), else: points
    end

    defp drop_closing(points), do: points

    defp area(points) when length(points) < 3, do: 0.0

    defp area(points) do
      points
      |> Enum.zip(tl(points) ++ [hd(points)])
      |> Enum.reduce(0.0, fn {{ax, ay}, {bx, by}}, sum -> sum + ax * by - bx * ay end)
      |> Kernel./(2)
    end

    defp planes(sector, points, pictures, sky) do
      [
        plane(sector.floor_picture, sector, points, sector.floor, {0.0, 0.0, 1.0}, pictures, sky),
        plane(
          sector.ceiling_picture,
          sector,
          Enum.reverse(points),
          sector.ceiling,
          {0.0, 0.0, -1.0},
          pictures,
          sky
        )
      ]
      |> Enum.reject(&is_nil/1)
    end

    defp plane(nil, _sector, _points, _height, _normal, _pictures, _sky), do: nil

    defp plane(picture, sector, points, height, normal, pictures, sky) do
      if MapSet.member?(sky, picture) do
        nil
      else
        {width, tall} = Pictures.size(pictures, picture)

        corners =
          Enum.map(points, fn {x, y} ->
            {{x, y, height}, normal, {x / width, -y / tall}, sector.light}
          end)

        {{:picture, picture}, corners}
      end
    end
  end
end
