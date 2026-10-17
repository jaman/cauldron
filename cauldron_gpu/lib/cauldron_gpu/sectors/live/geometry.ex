if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Live.Geometry do
    @moduledoc """
    The surfaces of a sector map sector by sector, from its sectors and sides as they are
    now: each sector's floors and ceilings over its subsectors' polygons
    (`CauldronGPU.Sectors.Flats.polygons/1`), and the walls facing into it
    (`CauldronGPU.Sectors.Walls`, with its pegging and sky rules). Floors and ceilings
    whose picture marks a sky, and the upper walls left out between two sky ceilings
    (from the lower ceiling up to the higher, facing into the higher sector), are sky
    surfaces keyed `:sky`.

    A surface is `{{:picture, id} | :sky, corners}`, each corner
    `{position, normal, uv, {sector, contrast}}` in map coordinates (+Z up): `sector` the
    sector it is lit by and `contrast` the light `-16`, `0` or `16` added for the wall's
    direction.

        geometry = CauldronGPU.Sectors.Live.Geometry.new(map)
        CauldronGPU.Sectors.Live.Geometry.surfaces(geometry, [3, 7], sectors, sides, pictures, sky)
        CauldronGPU.Sectors.Live.Geometry.neighbours(geometry, 3)
    """

    alias Cauldron2D.Sectors.Map, as: SectorMap
    alias Cauldron2D.Sectors.Pictures
    alias CauldronGPU.Sectors.{Flats, Walls}

    @label_step 64
    @label_middle 32

    @type corner :: {
            {number(), number(), number()},
            {number(), number(), number()},
            {number(), number()},
            {non_neg_integer(), integer()}
          }
    @type surface :: {{:picture, non_neg_integer()} | :sky, [corner()]}
    @type t :: %__MODULE__{
            map: SectorMap.t(),
            polygons: %{non_neg_integer() => [Flats.polygon()]},
            lines: %{non_neg_integer() => [non_neg_integer()]},
            neighbours: %{non_neg_integer() => MapSet.t(non_neg_integer())}
          }

    @enforce_keys [:map, :polygons, :lines, :neighbours]
    defstruct [:map, :polygons, :lines, :neighbours]

    @doc "The geometry of `map`, which must carry a BSP."
    @spec new(SectorMap.t()) :: t()
    def new(%SectorMap{} = map) do
      sided =
        map.lines |> Tuple.to_list() |> Enum.with_index() |> Enum.map(&line_sectors(map, &1))

      %__MODULE__{
        map: map,
        polygons: map |> Flats.polygons() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)),
        lines: lines_by_sector(sided),
        neighbours: neighbours(sided)
      }
    end

    @doc "The sectors sharing a two-sided line with `sector`."
    @spec neighbours(t(), non_neg_integer()) :: MapSet.t(non_neg_integer())
    def neighbours(%__MODULE__{neighbours: neighbours}, sector),
      do: Map.get(neighbours, sector, MapSet.new())

    @doc """
    The surfaces of each of `wanted`, as `%{sector => surfaces}`, given the map's
    `sectors` and `sides` as they are now; `sky` is the set of picture ids that mark a sky.
    """
    @spec surfaces(t(), [non_neg_integer()], tuple(), tuple(), Pictures.t(), MapSet.t()) ::
            %{non_neg_integer() => [surface()]}
    def surfaces(%__MODULE__{} = geometry, wanted, sectors, sides, pictures, sky) do
      empty = Map.new(wanted, &{&1, []})

      (walls(geometry, wanted, sectors, sides, pictures, sky) ++
         sky_walls(geometry, wanted, sectors, sides, sky) ++
         flats(geometry, wanted, sectors, pictures, sky))
      |> Enum.group_by(&surface_sector/1)
      |> Map.take(wanted)
      |> then(&Map.merge(empty, &1))
    end

    defp line_sectors(map, {line, index}) do
      {index, Enum.map([line.front, line.back], &side_sector(map, &1))}
    end

    defp side_sector(_map, nil), do: nil
    defp side_sector(map, side), do: elem(map.sides, side).sector

    defp lines_by_sector(sided) do
      for {index, sectors} <- sided,
          sector <- Enum.uniq(sectors),
          sector != nil,
          reduce: %{} do
        acc -> Map.update(acc, sector, [index], &[index | &1])
      end
    end

    defp neighbours(sided) do
      for {_index, [front, back]} <- sided,
          front != nil and back != nil and front != back,
          {from, to} <- [{front, back}, {back, front}],
          reduce: %{} do
        acc -> Map.update(acc, from, MapSet.new([to]), &MapSet.put(&1, to))
      end
    end

    defp surface_sector({_key, [{_position, _normal, _uv, {sector, _contrast}} | _corners]}),
      do: sector

    defp walls(geometry, wanted, sectors, sides, pictures, sky) do
      lines =
        wanted
        |> Enum.flat_map(&Map.get(geometry.lines, &1, []))
        |> Enum.uniq()
        |> Enum.map(&elem(geometry.map.lines, &1))
        |> List.to_tuple()

      %{geometry.map | lines: lines, sectors: labelled(sectors), sides: sides}
      |> Walls.surfaces(pictures, sky)
      |> Enum.map(fn {key, corners} -> {key, Enum.map(corners, &unlabel/1)} end)
    end

    defp labelled(sectors) do
      sectors
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.map(fn {sector, index} ->
        %{sector | light: index * @label_step + @label_middle}
      end)
      |> List.to_tuple()
    end

    defp unlabel({position, normal, uv, label}),
      do:
        {position, normal, uv, {div(label, @label_step), rem(label, @label_step) - @label_middle}}

    defp flats(geometry, wanted, sectors, pictures, sky) do
      for sector <- wanted,
          polygon <- Map.get(geometry.polygons, sector, []),
          surface <- planes(elem(sectors, sector), sector, polygon, pictures, sky),
          do: surface
    end

    defp planes(sector, index, points, pictures, sky) do
      [
        plane(sector.floor_picture, index, points, sector.floor, {0.0, 0.0, 1.0}, pictures, sky),
        plane(
          sector.ceiling_picture,
          index,
          Enum.reverse(points),
          sector.ceiling,
          {0.0, 0.0, -1.0},
          pictures,
          sky
        )
      ]
      |> Enum.reject(&is_nil/1)
    end

    defp plane(nil, _index, _points, _height, _normal, _pictures, _sky), do: nil

    defp plane(picture, index, points, height, normal, pictures, sky) do
      if MapSet.member?(sky, picture) do
        {:sky,
         Enum.map(points, fn {x, y} -> {{x, y, height}, normal, {0.0, 0.0}, {index, 0}} end)}
      else
        {width, tall} = Pictures.size(pictures, picture)

        {{:picture, picture},
         Enum.map(points, fn {x, y} ->
           {{x, y, height}, normal, {x / width, -y / tall}, {index, 0}}
         end)}
      end
    end

    defp sky_walls(geometry, wanted, sectors, sides, sky) do
      for sector <- wanted,
          index <- Map.get(geometry.lines, sector, []),
          line = elem(geometry.map.lines, index),
          line.back != nil,
          {own, other, ends} <- facing(geometry.map, index, line),
          elem(sides, own).sector == sector,
          front = elem(sectors, sector),
          back = elem(sectors, elem(sides, other).sector),
          back.ceiling < front.ceiling,
          MapSet.member?(sky, front.ceiling_picture) and MapSet.member?(sky, back.ceiling_picture),
          do: sky_wall(ends, back.ceiling, front.ceiling, sector)
    end

    defp facing(map, index, line) do
      {from, to} = SectorMap.ends(map, index)
      [{line.front, line.back, {from, to}}, {line.back, line.front, {to, from}}]
    end

    defp sky_wall({{sx, sy}, {fx, fy}}, bottom, top, sector) do
      length = :math.sqrt((fx - sx) * (fx - sx) + (fy - sy) * (fy - sy))
      normal = {(fy - sy) / length, -(fx - sx) / length, 0.0}

      corners =
        for {x, y, z} <- [{sx, sy, bottom}, {fx, fy, bottom}, {fx, fy, top}, {sx, sy, top}],
            do: {{x, y, z}, normal, {0.0, 0.0}, {sector, 0}}

      {:sky, corners}
    end
  end
end
