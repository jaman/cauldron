if Code.ensure_loaded?(Cauldron2D.Sectors.Map) do
  defmodule CauldronGPU.Sectors.Walls do
    @moduledoc """
    The walls of a sector map as `CauldronGPU.Sectors.Surfaces` surfaces, one quad per
    section of each side, keyed `{:picture, id}` and facing into the side's sector.

    A one-sided line shows its `middle` from floor to ceiling. A two-sided line shows its
    `upper` between the two ceilings, its `lower` between the two floors, and its `middle`
    once, not repeated, within the opening. Pictures follow Doom's pegging:

      * middle of a one-sided line: top at the ceiling; `:lower_unpegged`, bottom at
        the floor
      * upper: bottom at the lower ceiling; `:upper_unpegged`, top at the higher ceiling
      * lower: top at the higher floor; `:lower_unpegged`, placed as if hung from the
        side's own ceiling
      * middle of a two-sided line: top at the lower ceiling; `:lower_unpegged`, bottom
        at the higher floor

    `x_offset` and `y_offset` move the picture along and down the wall. Where both
    sectors' ceilings are in `sky`, the upper is left out. Lines running along the map's
    y axis are drawn 16 light levels brighter and along its x axis 16 darker.

        CauldronGPU.Sectors.Walls.surfaces(map, pictures, MapSet.new([sky_flat]))
    """

    alias Cauldron2D.Sectors.Map, as: SectorMap
    alias Cauldron2D.Sectors.Pictures
    alias CauldronGPU.Sectors.Surfaces

    @doc "Every wall section of `map`."
    @spec surfaces(SectorMap.t(), Pictures.t(), MapSet.t()) :: [Surfaces.surface()]
    def surfaces(%SectorMap{} = map, %Pictures{} = pictures, sky) do
      for index <- 0..(tuple_size(map.lines) - 1)//1,
          side <- [0, 1],
          wall = wall(map, index, side),
          wall != nil,
          section <- sections(wall, sky),
          surface = quad(wall, section, pictures),
          surface != nil,
          do: surface
    end

    defp wall(map, index, side) do
      line = elem(map.lines, index)

      case side_indices(line, side) do
        {nil, _other} ->
          nil

        {own, other} ->
          {start, finish} = ends(map, index, side)
          own_side = elem(map.sides, own)

          %{
            line: line,
            side: own_side,
            start: start,
            finish: finish,
            front: elem(map.sectors, own_side.sector),
            back: other && elem(map.sectors, elem(map.sides, other).sector)
          }
      end
    end

    defp side_indices(%{front: front, back: back}, 0), do: {front, back}
    defp side_indices(%{front: front, back: back}, 1), do: {back, front}

    defp ends(map, index, 0), do: SectorMap.ends(map, index)

    defp ends(map, index, 1) do
      {from, to} = SectorMap.ends(map, index)
      {to, from}
    end

    defp sections(%{back: nil} = wall, _sky) do
      [{:repeat, wall.side.middle, wall.front.floor, wall.front.ceiling, middle_top(wall)}]
    end

    defp sections(wall, sky) do
      Enum.reject([upper(wall, sky), lower(wall), masked(wall)], &is_nil/1)
    end

    defp middle_top(%{line: line, front: front}) do
      if MapSet.member?(line.flags, :lower_unpegged),
        do: {:bottom, front.floor},
        else: {:top, front.ceiling}
    end

    defp upper(%{front: front, back: back} = wall, sky) do
      cond do
        back.ceiling >= front.ceiling ->
          nil

        MapSet.member?(sky, front.ceiling_picture) and MapSet.member?(sky, back.ceiling_picture) ->
          nil

        MapSet.member?(wall.line.flags, :upper_unpegged) ->
          {:repeat, wall.side.upper, back.ceiling, front.ceiling, {:top, front.ceiling}}

        true ->
          {:repeat, wall.side.upper, back.ceiling, front.ceiling, {:bottom, back.ceiling}}
      end
    end

    defp lower(%{front: front, back: back} = wall) do
      cond do
        back.floor <= front.floor ->
          nil

        MapSet.member?(wall.line.flags, :lower_unpegged) ->
          {:repeat, wall.side.lower, front.floor, back.floor, {:top, front.ceiling}}

        true ->
          {:repeat, wall.side.lower, front.floor, back.floor, {:top, back.floor}}
      end
    end

    defp masked(%{side: %{middle: nil}}), do: nil

    defp masked(%{front: front, back: back} = wall) do
      low = max(front.floor, back.floor)
      high = min(front.ceiling, back.ceiling)

      anchor =
        if MapSet.member?(wall.line.flags, :lower_unpegged),
          do: {:bottom, low},
          else: {:top, high}

      {:once, wall.side.middle, low, high, anchor}
    end

    defp quad(_wall, {_kind, nil, _bottom, _top, _anchor}, _pictures), do: nil

    defp quad(wall, {kind, picture, bottom, top, anchor}, pictures) do
      {width, height} = Pictures.size(pictures, picture)
      texture_top = texture_top(anchor, height) + wall.side.y_offset
      {bottom, top} = span(kind, bottom, top, texture_top, height)

      if top > bottom do
        {{:picture, picture}, corners(wall, bottom, top, texture_top, width, height)}
      end
    end

    defp texture_top({:top, z}, _height), do: z
    defp texture_top({:bottom, z}, height), do: z + height

    defp span(:repeat, bottom, top, _texture_top, _height), do: {bottom, top}

    defp span(:once, bottom, top, texture_top, height),
      do: {max(bottom, texture_top - height), min(top, texture_top)}

    defp corners(wall, bottom, top, texture_top, width, height) do
      {sx, sy} = wall.start
      {fx, fy} = wall.finish
      length = :math.sqrt((fx - sx) * (fx - sx) + (fy - sy) * (fy - sy))
      normal = {(fy - sy) / length, -(fx - sx) / length, 0.0}
      light = wall.front.light + contrast(wall.start, wall.finish)
      u0 = wall.side.x_offset / width
      u1 = (wall.side.x_offset + length) / width
      v_bottom = (texture_top - bottom) / height
      v_top = (texture_top - top) / height

      [
        {{sx, sy, bottom}, normal, {u0, v_bottom}, light},
        {{fx, fy, bottom}, normal, {u1, v_bottom}, light},
        {{fx, fy, top}, normal, {u1, v_top}, light},
        {{sx, sy, top}, normal, {u0, v_top}, light}
      ]
    end

    defp contrast({_sx, sy}, {_fx, fy}) when sy == fy, do: -16
    defp contrast({sx, _sy}, {fx, _fy}) when sx == fx, do: 16
    defp contrast(_start, _finish), do: 0
  end
end
