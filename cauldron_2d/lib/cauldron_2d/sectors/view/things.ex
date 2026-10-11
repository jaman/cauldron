defmodule Cauldron2D.Sectors.View.Things do
  @moduledoc false

  alias Cauldron2D.Sectors.{Frame, Pictures, View}
  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.View.Walls

  @nearest 4.0
  @shimmer_table 6

  def draw(frame, state, things) do
    sprites =
      things
      |> Enum.filter(&MapSet.member?(state.visible, &1.sector))
      |> Enum.flat_map(&project(state, &1))
      |> Enum.sort_by(& &1.depth, :desc)

    drawsegs = Enum.with_index(state.drawsegs)

    {records, drawn} =
      Enum.reduce(sprites, {[], MapSet.new()}, fn sprite, {records, drawn} ->
        sprite_records(state, sprite, drawsegs, records, drawn)
      end)

    {records, _drawn} =
      Enum.reduce(drawsegs, {records, drawn}, fn {ds, id}, acc ->
        if ds.masked, do: masked_range(state, {ds, id}, ds.x1, ds.x2, acc), else: acc
      end)

    {Frame.columns(frame, state.pictures, Enum.reverse(records)), state}
  end

  defp project(state, thing) do
    tr_x = thing.x - state.vx
    tr_y = thing.y - state.vy
    {cosine, sine} = {:math.cos(state.angle), :math.sin(state.angle)}
    depth = tr_x * cosine + tr_y * sine

    if depth < @nearest do
      []
    else
      sprite(state, thing, depth, tr_x * sine - tr_y * cosine)
    end
  end

  defp sprite(state, thing, depth, across) do
    {left, top} = Map.get(thing, :offset, {0, 0})
    {width, height} = Pictures.size(state.pictures, thing.picture)
    x_scale = state.focal_x / depth
    y_scale = state.focal_y / depth
    start = state.center_x + (across - left) * x_scale
    finish = state.center_x + (across - left + width) * x_scale
    x1 = max(Walls.ceil_row(start), 0)
    x2 = min(Walls.ceil_row(finish) - 1, state.width - 1)

    if x1 > x2 do
      []
    else
      texture_mid = thing.z + top - state.vz

      [
        %{
          x1: x1,
          x2: x2,
          start: start,
          depth: depth,
          x_scale: x_scale,
          y_scale: y_scale,
          width: width,
          height: height,
          picture: thing.picture,
          flip: Map.get(thing, :flip, false),
          texture_mid: texture_mid,
          bottom_z: thing.z,
          top_z: thing.z + top,
          at: {thing.x, thing.y},
          shimmer: Map.get(thing, :shimmer, false),
          light: sprite_light(state, thing, depth)
        }
      ]
    end
  end

  defp sprite_light(state, %{shimmer: true}, _depth), do: state.fixed || @shimmer_table

  defp sprite_light(state, thing, depth) do
    cond do
      state.fixed -> state.fixed
      Map.get(thing, :bright, false) -> 0
      true -> View.light_table(state, elem(state.sectors, thing.sector).light, depth)
    end
  end

  defp sprite_records(state, sprite, drawsegs, records, drawn) do
    {clips, records, drawn} =
      Enum.reduce(drawsegs, {%{}, records, drawn}, fn {ds, id}, {clips, records, drawn} ->
        clip_against(state, sprite, {ds, id}, clips, records, drawn)
      end)

    columns =
      for x <- sprite.x1..sprite.x2 do
        {top_clip, bottom_clip} = Map.get(clips, x, {nil, nil})
        sprite_column(state, sprite, x, top_clip || -1, bottom_clip || state.height)
      end

    {Enum.reverse(Enum.reject(columns, &is_nil/1), records), drawn}
  end

  defp clip_against(state, sprite, {ds, id}, clips, records, drawn) do
    cond do
      not overlaps?(ds, sprite) or not clips_anything?(ds) ->
        {clips, records, drawn}

      behind?(ds, sprite) ->
        {records, drawn} = masked_behind(state, sprite, {ds, id}, {records, drawn})
        {clips, records, drawn}

      true ->
        {silhouette_clips(state, sprite, ds, clips), records, drawn}
    end
  end

  defp overlaps?(ds, sprite), do: ds.x1 <= sprite.x2 and ds.x2 >= sprite.x1

  defp clips_anything?(ds),
    do: ds.silhouette.solid or ds.silhouette.top or ds.silhouette.bottom or ds.masked != nil

  defp masked_behind(_state, _sprite, {%{masked: nil}, _id}, acc), do: acc

  defp masked_behind(state, sprite, {ds, id}, acc),
    do: masked_range(state, {ds, id}, max(ds.x1, sprite.x1), min(ds.x2, sprite.x2), acc)

  defp behind?(ds, sprite) do
    {fx, fy} = ds.seg.from
    {tx, ty} = ds.seg.to

    ds.near > sprite.depth or
      (ds.far > sprite.depth and SectorMap.point_side(sprite.at, {fx, fy, tx - fx, ty - fy}) == 0)
  end

  defp silhouette_clips(state, sprite, ds, clips) do
    silhouette = ds.silhouette
    low = max(ds.x1, sprite.x1)
    high = min(ds.x2, sprite.x2)

    {top?, bottom?} =
      if silhouette.solid,
        do: {true, true},
        else:
          {silhouette.top and not at_or_below?(sprite.top_z, silhouette.top_height),
           silhouette.bottom and not at_or_above?(sprite.bottom_z, silhouette.bottom_height)}

    Enum.reduce(low..high, clips, fn x, acc ->
      {top, bottom} = Map.get(acc, x, {nil, nil})
      top = if top == nil and top?, do: top_clip(state, ds, x), else: top
      bottom = if bottom == nil and bottom?, do: bottom_clip(ds, x), else: bottom
      Map.put(acc, x, {top, bottom})
    end)
  end

  defp at_or_below?(_z, :neg_infinity), do: false
  defp at_or_below?(_z, nil), do: false
  defp at_or_below?(z, height), do: z <= height

  defp at_or_above?(_z, :infinity), do: false
  defp at_or_above?(_z, nil), do: false
  defp at_or_above?(z, height), do: z >= height

  defp top_clip(state, %{silhouette: %{solid: true}}, _x), do: state.height
  defp top_clip(state, %{silhouette: %{top_kind: :all}}, _x), do: state.height
  defp top_clip(_state, ds, x), do: elem(ds.top_clips, x - ds.x1)

  defp bottom_clip(%{silhouette: %{solid: true}}, _x), do: -1
  defp bottom_clip(%{silhouette: %{bottom_kind: :none}}, _x), do: -1
  defp bottom_clip(ds, x), do: elem(ds.bottom_clips, x - ds.x1)

  defp sprite_column(state, sprite, x, top_clip, bottom_clip) do
    u = floor((x + 0.5 - sprite.start) / sprite.x_scale)
    u = if sprite.flip, do: sprite.width - 1 - u, else: u
    top = Walls.ceil_row(state.center_y - sprite.texture_mid * sprite.y_scale)

    bottom =
      Walls.ceil_row(state.center_y - (sprite.texture_mid - sprite.height) * sprite.y_scale) - 1

    first = max(top, top_clip + 1)
    last = min(bottom, bottom_clip - 1)

    if first > last or u < 0 or u >= sprite.width do
      nil
    else
      v = sprite.texture_mid - (state.center_y - (first + 0.5)) / sprite.y_scale

      Frame.column(x, {first, last}, sprite.picture, {u, v, 1.0 / sprite.y_scale}, sprite.light,
        masked: true,
        shimmer: sprite.shimmer
      )
    end
  end

  defp masked_range(state, {ds, id}, low, high, {records, drawn}) do
    texture = ds.masked.texture

    Enum.reduce(low..high//1, {records, drawn}, fn x, {acc, seen} ->
      if MapSet.member?(seen, {id, x}) do
        {acc, seen}
      else
        {[masked_column(state, ds, texture, x) | acc], MapSet.put(seen, {id, x})}
      end
    end)
  end

  defp masked_column(state, ds, texture, x) do
    index = x - ds.x1
    {u, light} = elem(ds.masked.columns, index)
    depth = elem(ds.depths, index)
    y_scale = state.focal_y / depth
    texture_mid = texture.top - state.vz + ds.masked.y_offset
    top = Walls.ceil_row(state.center_y - texture_mid * y_scale)
    bottom = Walls.ceil_row(state.center_y - (texture_mid - texture.height) * y_scale) - 1
    first = max(top, elem(ds.top_clips, index) + 1)
    last = min(bottom, elem(ds.bottom_clips, index) - 1)
    column = Integer.mod(floor(u), texture.width)
    v = texture_mid - (state.center_y - (first + 0.5)) / y_scale

    if first > last,
      do: <<>>,
      else:
        Frame.column(x, {first, last}, texture.picture, {column, v, 1.0 / y_scale}, light,
          masked: true
        )
  end
end
