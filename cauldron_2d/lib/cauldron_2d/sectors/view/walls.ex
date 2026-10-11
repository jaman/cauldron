defmodule Cauldron2D.Sectors.View.Walls do
  @moduledoc false

  alias Cauldron2D.Sectors.{Frame, Pictures, View}

  @max_scale 64.0

  def store(state, seg, front, back, first, last) do
    side = View.side_of(state, seg)
    line = elem(state.map.lines, seg.line)
    wall = wall(state, seg, side, line, front, back)

    {state, floor_id} =
      if wall.mark_floor,
        do: View.check_plane(state, state.floor_plane, first, last),
        else: {state, nil}

    {state, ceiling_id} =
      if wall.mark_ceiling,
        do: View.check_plane(state, state.ceiling_plane, first, last),
        else: {state, nil}

    wall = %{
      wall
      | mark_floor: wall.mark_floor and floor_id != nil,
        mark_ceiling: wall.mark_ceiling and ceiling_id != nil
    }

    count = last - first + 1
    ceiling_clips = decode(binary_part(state.ceiling_clip, first * 2, count * 2))
    floor_clips = decode(binary_part(state.floor_clip, first * 2, count * 2))

    {columns, state} =
      [first..last//1, ceiling_clips, floor_clips]
      |> Enum.zip()
      |> Enum.map_reduce(state, fn {x, ceiling, floor}, acc ->
        column(acc, wall, x, ceiling, floor, {floor_id, ceiling_id})
      end)

    new_ceiling = Enum.map(columns, & &1.ceiling)
    new_floor = Enum.map(columns, & &1.floor)

    state = %{
      state
      | ceiling_clip: splice(state.ceiling_clip, first, new_ceiling),
        floor_clip: splice(state.floor_clip, first, new_floor),
        walls: [Enum.map(columns, & &1.records) | state.walls],
        seen: MapSet.put(state.seen, seg.line)
    }

    %{state | drawsegs: [drawseg(wall, seg, first, last, columns) | state.drawsegs]}
  end

  defp wall(state, seg, side, line, front, back) do
    {fx, fy} = seg.from
    {tx, ty} = seg.to
    length = :math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy))

    sky_both? =
      back != nil and View.sky?(state, front.ceiling_picture) and
        View.sky?(state, back.ceiling_picture)

    world_top = front.ceiling - state.vz
    world_bottom = front.floor - state.vz
    world_high = if back, do: back.ceiling - state.vz
    world_low = if back, do: back.floor - state.vz
    world_top = if sky_both?, do: world_high, else: world_top
    flags = line.flags

    base = %{
      seg: seg,
      from: seg.from,
      along: {tx - fx, ty - fy},
      length: length,
      u_start: seg.offset + side.x_offset,
      y_offset: side.y_offset,
      light: front.light + contrast(state, seg),
      world_top: world_top,
      world_bottom: world_bottom,
      world_high: world_high,
      world_low: world_low,
      back?: back != nil,
      middle: nil,
      upper: nil,
      lower: nil,
      masked: nil,
      mark_floor: true,
      mark_ceiling: true,
      silhouette: %{top: false, bottom: false, top_height: nil, bottom_height: nil}
    }

    shaped =
      if back == nil,
        do: solid(base, state, side, flags, front),
        else: two_sided(base, state, side, flags, front, back)

    visible_planes(shaped, state, front)
  end

  defp contrast(state, %{from: {fx, fy}, to: {tx, ty}}) do
    cond do
      fy == ty -> -state.contrast
      fx == tx -> state.contrast
      true -> 0
    end
  end

  defp solid(base, state, side, flags, front) do
    middle =
      textured(state, side.middle, fn height ->
        if MapSet.member?(flags, :lower_unpegged), do: front.floor + height, else: front.ceiling
      end)

    %{base | middle: middle}
  end

  defp two_sided(base, state, side, flags, front, back) do
    upper =
      if base.world_high < base.world_top,
        do: textured(state, side.upper, &upper_top(flags, front, back, &1))

    lower =
      if base.world_low > base.world_bottom,
        do: textured(state, side.lower, fn _height -> lower_top(flags, front, back) end)

    masked = textured(state, side.middle, &masked_top(flags, front, back, &1))

    %{
      base
      | upper: upper,
        lower: lower,
        masked: masked,
        mark_floor: mark_floor?(base, front, back),
        mark_ceiling: mark_ceiling?(base, front, back),
        silhouette: silhouette(state, front, back, masked)
    }
  end

  defp closed?(front, back), do: back.ceiling <= front.floor or back.floor >= front.ceiling

  defp mark_floor?(base, front, back) do
    closed?(front, back) or base.world_low != base.world_bottom or
      back.floor_picture != front.floor_picture or back.light != front.light
  end

  defp mark_ceiling?(base, front, back) do
    closed?(front, back) or base.world_high != base.world_top or
      back.ceiling_picture != front.ceiling_picture or back.light != front.light
  end

  defp upper_top(flags, front, back, height),
    do: if(MapSet.member?(flags, :upper_unpegged), do: front.ceiling, else: back.ceiling + height)

  defp lower_top(flags, front, back),
    do: if(MapSet.member?(flags, :lower_unpegged), do: front.ceiling, else: back.floor)

  defp masked_top(flags, front, back, height) do
    if MapSet.member?(flags, :lower_unpegged),
      do: max(front.floor, back.floor) + height,
      else: min(front.ceiling, back.ceiling)
  end

  defp silhouette(state, front, back, masked) do
    {bottom?, bottom_height, bottom_kind} = bottom_silhouette(state, front, back, masked)
    {top?, top_height, top_kind} = top_silhouette(state, front, back, masked)

    %{
      top: top?,
      bottom: bottom?,
      top_height: top_height,
      bottom_height: bottom_height,
      top_kind: top_kind,
      bottom_kind: bottom_kind
    }
  end

  defp bottom_silhouette(state, front, back, masked) do
    cond do
      back.ceiling <= front.floor -> {true, :infinity, :none}
      front.floor > back.floor -> {true, front.floor, :clip}
      back.floor > state.vz -> {true, :infinity, :clip}
      masked != nil -> {true, :infinity, :clip}
      true -> {false, nil, :clip}
    end
  end

  defp top_silhouette(state, front, back, masked) do
    cond do
      back.floor >= front.ceiling -> {true, :neg_infinity, :all}
      front.ceiling < back.ceiling -> {true, front.ceiling, :clip}
      back.ceiling < state.vz -> {true, :neg_infinity, :clip}
      masked != nil -> {true, :neg_infinity, :clip}
      true -> {false, nil, :clip}
    end
  end

  defp visible_planes(wall, state, front) do
    %{
      wall
      | mark_floor: wall.mark_floor and front.floor < state.vz,
        mark_ceiling:
          wall.mark_ceiling and
            (front.ceiling > state.vz or View.sky?(state, front.ceiling_picture))
    }
  end

  defp textured(_state, nil, _top), do: nil

  defp textured(state, picture, top) do
    {width, height} = Pictures.size(state.pictures, picture)
    %{picture: picture, width: width, height: height, top: top.(height)}
  end

  defp column(state, wall, x, ceiling, floor, {floor_id, ceiling_id}) do
    {rx, ry, cosine} = elem(state.rays, x)
    {ex, ey} = wall.along
    {wx, wy} = {elem(wall.from, 0) - state.vx, elem(wall.from, 1) - state.vy}
    denominator = rx * ey - ry * ex

    {s, t} =
      if abs(denominator) < 1.0e-12,
        do: {1.0e9, 0.0},
        else: {(wx * ey - wy * ex) / denominator, (wx * ry - wy * rx) / denominator}

    depth = max(s * cosine, state.focal_x / @max_scale)
    y_scale = state.focal_y / depth
    u = wall.u_start + min(max(t, 0.0), 1.0) * wall.length
    light = View.light_table(state, wall.light, depth)

    top_row = ceil_row(state.center_y - wall.world_top * y_scale)
    bottom_row = ceil_row(state.center_y - wall.world_bottom * y_scale) - 1
    yl = max(top_row, ceiling + 1)
    yh = min(bottom_row, floor - 1)

    state =
      if wall.mark_ceiling,
        do: View.mark_plane(state, ceiling_id, x, ceiling + 1, min(yl - 1, floor - 1)),
        else: state

    state =
      if wall.mark_floor,
        do: View.mark_plane(state, floor_id, x, max(yh + 1, ceiling + 1), floor - 1),
        else: state

    context = %{x: x, u: u, y_scale: y_scale, light: light, depth: depth}

    result =
      if wall.back?,
        do: two_sided_column(state, wall, context, {yl, yh}, {ceiling, floor}),
        else: solid_column(state, wall, context, {yl, yh})

    {Map.merge(result, %{x: x, depth: depth, u: u, light: light}), state}
  end

  defp solid_column(state, wall, context, {yl, yh}) do
    records =
      if wall.middle && yl <= yh,
        do: [record(state, wall, wall.middle, context, yl, yh)],
        else: []

    %{records: records, ceiling: state.height, floor: -1}
  end

  defp two_sided_column(state, wall, context, {yl, yh}, {ceiling, floor}) do
    {upper_records, ceiling} =
      cond do
        wall.upper != nil ->
          mid = min(ceil_row(state.center_y - wall.world_high * context.y_scale) - 1, floor - 1)

          if mid >= yl,
            do: {[record(state, wall, wall.upper, context, yl, mid)], mid},
            else: {[], yl - 1}

        wall.mark_ceiling ->
          {[], yl - 1}

        true ->
          {[], ceiling}
      end

    {lower_records, floor} =
      cond do
        wall.lower != nil ->
          mid = max(ceil_row(state.center_y - wall.world_low * context.y_scale), ceiling + 1)

          if mid <= yh,
            do: {[record(state, wall, wall.lower, context, mid, yh)], mid},
            else: {[], yh + 1}

        wall.mark_floor ->
          {[], yh + 1}

        true ->
          {[], floor}
      end

    %{records: upper_records ++ lower_records, ceiling: ceiling, floor: floor}
  end

  defp record(state, wall, texture, context, top, bottom) do
    base = texture.top - state.vz + wall.y_offset
    v = base - (state.center_y - (top + 0.5)) / context.y_scale
    column = floor(context.u)

    Frame.column(
      context.x,
      {top, bottom},
      texture.picture,
      {column, v, 1.0 / context.y_scale},
      context.light
    )
  end

  @doc false
  def ceil_row(y), do: y |> Kernel.-(0.5) |> Float.ceil() |> trunc()

  defp drawseg(wall, seg, first, last, columns) do
    depths = columns |> Enum.map(& &1.depth) |> List.to_tuple()

    %{
      x1: first,
      x2: last,
      seg: seg,
      depths: depths,
      near: depths |> Tuple.to_list() |> Enum.min(),
      far: depths |> Tuple.to_list() |> Enum.max(),
      silhouette: drawseg_silhouette(wall),
      top_clips: columns |> Enum.map(& &1.ceiling) |> List.to_tuple(),
      bottom_clips: columns |> Enum.map(& &1.floor) |> List.to_tuple(),
      masked: masked_columns(wall, columns)
    }
  end

  defp drawseg_silhouette(%{back?: false}), do: %{solid: true}

  defp drawseg_silhouette(%{silhouette: silhouette}), do: Map.put(silhouette, :solid, false)

  defp masked_columns(%{masked: nil}, _columns), do: nil

  defp masked_columns(%{masked: texture, y_offset: y_offset}, columns) do
    %{
      texture: texture,
      y_offset: y_offset,
      columns: columns |> Enum.map(&{&1.u, &1.light}) |> List.to_tuple()
    }
  end

  defp decode(binary), do: for(<<value::16-little-signed <- binary>>, do: value)

  defp splice(binary, first, values) do
    count = length(values)
    head = binary_part(binary, 0, first * 2)
    tail = binary_part(binary, (first + count) * 2, byte_size(binary) - (first + count) * 2)
    middle = for value <- values, into: <<>>, do: <<value::16-little-signed>>
    head <> middle <> tail
  end
end
