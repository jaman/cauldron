defmodule Cauldron2D.Projection.FirstPerson do
  @moduledoc """
  Renders the world from a point inside it, looking along a heading: standing arts as
  textured walls of their height, floors textured to the horizon, movers and the
  standing arts of no height as billboards, everything fading towards the atlas's void
  colour with distance.

      Cauldron2D.Projection.FirstPerson.render(:my_game,
        position: {12.5, 8.5},
        heading: :math.pi() / 2,
        cell: &MyGame.cell/1,
        size: {320, 200},
        movers: [{:guard, {14.5, 8.5}, 0.0}]
      )

  ## Options

    * `:position` — `{x, y}` in tiles, where the eye is, required
    * `:heading` — radians, `0` along `+x`, required
    * `:cell` — `fn {x, y} -> cell end`, as `Cauldron2D.Surface` takes cells; `:void`
      ends a ray, required
    * `:size` — `{width, height}` of the picture in pixels, required
    * `:eye` — how far above the ground the eye is, in tiles, so that a figure of a given
      height looks out from its own head rather than a fixed point. A cell is one tile
      across and a storey one tile tall, so an art standing `1.5` tiles looks from about
      `1.35`; `Cauldron2D.Atlas.eye_height/2` answers for an art. Default `0.6`
    * `:pitch` — `-1.0..1.0`, how far the horizon is moved down or up the picture.
      Default `0.0`
    * `:aspect` — a pixel's width over its height, so a picture drawn into cells
      that are not square keeps its proportions. Default `1.0`
    * `:fov` — the horizontal field of view in degrees. Default `70`
    * `:range` — how many tiles away things fade out entirely. Default `24`
    * `:sky` — `{top, bottom}` colours above the horizon. Default a blue gradient
    * `:movers` — `[{art, {x, y}}]` or `[{art, {x, y}, heading}]`; a mover shows its
      `:front` pose when heading towards the eye, `:back` away, `:side` across
      (mirrored one way); with no heading it faces the eye. Default `[]`
    * `:volumes` — coloured regions of space, as `Cauldron2D.Projection.Volume`
      describes them, tinting whatever the eye sees through them and nothing in front of
      them. Default `[]`
    * `:at` — the time in milliseconds an animated art's frame is chosen for. Default `0`

  A wall is the cell's standing arts stacked, base first then its overlays in order,
  each the storeys of its height with the face towards the eye — `:north`, `:east`,
  `:south` or `:west`, else `:side` — as its texture, repeated per storey. A floor is
  the base's `:top` face. An
  overlay of height `0` stands at its tile's centre facing the eye, drawn as a mover
  with no heading is, at its own size against the tile.
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{Canvas, Volume}
  alias FrenchCurve.Raster

  @eye 0.6
  @fog_levels 6
  @near 0.15
  @max_steps 96
  @default_sky {{24, 30, 58}, {96, 120, 170}}

  @type option ::
          {:position, {number(), number()}}
          | {:heading, number()}
          | {:cell, ({integer(), integer()} -> Cauldron2D.Surface.cell())}
          | {:size, {pos_integer(), pos_integer()}}
          | {:pitch, number()}
          | {:aspect, number()}
          | {:fov, number()}
          | {:eye, number()}
          | {:range, number()}
          | {:sky, {{byte(), byte(), byte()}, {byte(), byte(), byte()}}}
          | {:movers, [tuple()]}
          | {:volumes, [map()]}
          | {:at, integer()}

  @doc "The picture, as the module documentation describes."
  @spec render(Atlas.name() | Atlas.t(), [option()]) :: Raster.t()
  def render(atlas, opts) do
    atlas = Atlas.fetch(atlas)
    {width, height} = Keyword.fetch!(opts, :size)
    heading = Keyword.fetch!(opts, :heading)
    pitch = opts |> Keyword.get(:pitch, 0.0) |> min(1.0) |> max(-1.0)
    horizon = height / 2 + pitch * height / 2
    fov = Keyword.get(opts, :fov, 70) * :math.pi() / 180
    tan_half = :math.tan(fov / 2)
    projection = width / 2 / tan_half
    direction = {:math.cos(heading), :math.sin(heading)}
    perpendicular = {-:math.sin(heading), :math.cos(heading)}

    context = %{
      atlas: atlas,
      table: Atlas.cache(atlas.name),
      cell: Keyword.fetch!(opts, :cell),
      at: Keyword.get(opts, :at, 0),
      eye: Keyword.get(opts, :eye, @eye) / 1,
      horizon: horizon,
      projection: projection,
      vertical: projection / Keyword.get(opts, :aspect, 1.0),
      position: Keyword.fetch!(opts, :position),
      range: Keyword.get(opts, :range, 24) / 1,
      sky: sky(height, horizon, Keyword.get(opts, :sky, @default_sky)),
      void:
        Map.new(
          0..@fog_levels,
          &{&1, Canvas.shade(void_pixel(atlas), 1.0, atlas.void, &1 / @fog_levels)}
        )
    }

    columns =
      Map.new(0..(width - 1)//1, fn x ->
        ray = ray(direction, perpendicular, tan_half, 2 * (x + 0.5) / width - 1)
        {x, {cast(context, ray), ray}}
      end)

    columns =
      standing_props(context)
      |> Kernel.++(Keyword.get(opts, :movers, []))
      |> Enum.reduce(
        columns,
        &billboard(&1, &2, context, direction, perpendicular, tan_half, width)
      )
      |> Enum.map(fn {x, {spans, {rx, ry}}} ->
        {x, {Enum.sort_by(spans, &elem(&1, 1)), rx, ry}}
      end)
      |> Enum.sort()
      |> Enum.map(&elem(&1, 1))
      |> List.to_tuple()

    eyes = %{direction: direction, perpendicular: perpendicular}

    case Volume.list(Keyword.get(opts, :volumes, [])) do
      [] -> Raster.from_rgba(width, height, flat(columns, {width, height}, context))
      volumes -> seen_through(columns, volumes, {width, height}, context, eyes)
    end
  end

  defp flat(columns, {width, height}, context) do
    for y <- 0..(height - 1)//1, x <- 0..(width - 1)//1, into: <<>> do
      pixel(elem(columns, x), y, context)
    end
  end

  defp pixel({spans, ray_x, ray_y}, y, context) do
    yc = y + 0.5

    case drawn(spans, yc, context) do
      nil ->
        if yc <= context.horizon,
          do: elem(context.sky, y),
          else: floor_pixel(ray_x, ray_y, yc, context)

      found ->
        found
    end
  end

  defp drawn([], _yc, _context), do: nil

  defp drawn([span | rest], yc, context) do
    if yc >= elem(span, 2) and yc <= elem(span, 3) do
      case span_pixel(span, yc, context) do
        <<_, _, _, alpha>> = found when alpha >= 128 -> found
        _clear -> drawn(rest, yc, context)
      end
    else
      drawn(rest, yc, context)
    end
  end

  defp floor_pixel(ray_x, ray_y, yc, context) do
    {pixel, _distance} = floor_seen(ray_x, ray_y, yc, context)
    pixel
  end

  defp seen_through(columns, volumes, {width, height}, context, eyes) do
    {rows, reaches} =
      Enum.map_reduce(0..(height - 1)//1, [], fn y, held ->
        {pixels, limits} = looked_at(columns, y, width, context)
        {{y, pixels}, [limits | held]}
      end)

    {px, py} = context.position
    limits = reaches |> Enum.reverse() |> IO.iodata_to_binary()
    plan = Volume.eye_plan({px, py, context.eye}, &looking(&1, context, eyes, width), limits)
    canvas = %{width: width, height: height, rows: Map.new(rows)}

    volumes
    |> Enum.reduce(canvas, fn volume, acc ->
      Volume.paint(acc, volume, volume_box(volume, context, eyes, {width, height}), plan)
    end)
    |> Canvas.to_raster()
  end

  defp looked_at(columns, y, width, context) do
    Enum.reduce(0..(width - 1)//1, {<<>>, <<>>}, fn x, {pixels, limits} ->
      {pixel, as_far_as} = surface(elem(columns, x), y, context)

      {<<pixels::binary, pixel::binary>>, <<limits::binary, far(as_far_as)::float-native-32>>}
    end)
  end

  defp far(:infinity), do: 1.0e18
  defp far(distance), do: distance / 1

  defp looking({px, py}, context, %{direction: {dx, dy}, perpendicular: {rx, ry}}, width) do
    side = (px - width / 2) / context.projection

    {dx + rx * side, dy + ry * side, (context.horizon - py) / context.vertical}
  end

  defp volume_box(volume, context, eyes, {width, height}) do
    {cx, cy} = volume.at
    {px, py} = context.position
    {dx, dy} = eyes.direction

    if (cx - px) * dx + (cy - py) * dy - Volume.reach(volume) < @near,
      do: {0, 0, width - 1, height - 1},
      else: Volume.box(volume, &screen_point(&1, context, eyes, width))
  end

  defp screen_point({x, y, z}, context, %{direction: {dx, dy}, perpendicular: {rx, ry}}, width) do
    {px, py} = context.position
    depth = (x - px) * dx + (y - py) * dy
    lateral = (x - px) * rx + (y - py) * ry

    if depth > @near do
      {width / 2 + lateral * context.projection / depth,
       context.horizon + (context.eye - z) * context.vertical / depth}
    end
  end

  defp void_pixel(%{void: {red, green, blue}}), do: <<red, green, blue, 255>>

  defp ray({dx, dy}, {px, py}, tan_half, camera_x),
    do: {dx + px * tan_half * camera_x, dy + py * tan_half * camera_x}

  defp sky(height, horizon, {{tr, tg, tb}, {br, bg, bb}}) do
    for y <- 0..(height - 1)//1 do
      mix = min(1.0, y / max(horizon, 1))

      <<round(tr + (br - tr) * mix), round(tg + (bg - tg) * mix), round(tb + (bb - tb) * mix),
        255>>
    end
    |> List.to_tuple()
  end

  defp cast(context, {ray_x, ray_y}) do
    {px, py} = context.position
    map_x = floor(px)
    map_y = floor(py)
    delta_x = if ray_x == 0, do: 1.0e30, else: abs(1 / ray_x)
    delta_y = if ray_y == 0, do: 1.0e30, else: abs(1 / ray_y)

    {step_x, side_x} =
      if ray_x < 0, do: {-1, (px - map_x) * delta_x}, else: {1, (map_x + 1 - px) * delta_x}

    {step_y, side_y} =
      if ray_y < 0, do: {-1, (py - map_y) * delta_y}, else: {1, (map_y + 1 - py) * delta_y}

    walk(
      context,
      {ray_x, ray_y},
      %{x: map_x, y: map_y, side_x: side_x, side_y: side_y},
      {step_x, step_y, delta_x, delta_y},
      context.horizon + 1,
      0,
      []
    )
  end

  defp walk(_context, _ray, _at, _stepping, _top, @max_steps, spans), do: spans

  defp walk(context, ray, at, {step_x, step_y, delta_x, delta_y} = stepping, top, steps, spans) do
    {at, side, distance} =
      if at.side_x < at.side_y,
        do: {%{at | side_x: at.side_x + delta_x, x: at.x + step_x}, 0, at.side_x},
        else: {%{at | side_y: at.side_y + delta_y, y: at.y + step_y}, 1, at.side_y}

    if distance > context.range or top <= 0 do
      spans
    else
      case block(context, {at.x, at.y}) do
        :void ->
          spans

        [] ->
          walk(context, ray, at, stepping, top, steps + 1, spans)

        stack ->
          {top, spans} = stacked(context, ray, stack, side, distance, top, spans)
          walk(context, ray, at, stepping, top, steps + 1, spans)
      end
    end
  end

  defp stacked(context, ray, stack, side, distance, top, spans) do
    {_storeys, top, spans} =
      Enum.reduce(stack, {0, top, spans}, fn {art, height}, {from, top, spans} ->
        span = wall_span(context, ray, art, {from, height}, side, distance)
        {top, spans} = nearer(span, top, spans)
        {from + height, top, spans}
      end)

    {top, spans}
  end

  defp nearer({_, _, span_top, _, _, _, _} = span, top, spans) when span_top < top,
    do: {span_top, [span | spans]}

  defp nearer(_span, top, spans), do: {top, spans}

  defp block(context, position) do
    case context.cell.(position) do
      :void ->
        :void

      {base, overlays, _tint} ->
        for art <- [base | overlays],
            %{height: height} = Atlas.entry(context.atlas, art),
            height > 0,
            do: {art, height}
    end
  end

  defp wall_span(context, {ray_x, ray_y}, art, {from, storeys}, side, distance) do
    {px, py} = context.position
    scale = context.vertical / max(distance, 1.0e-6)
    hit = if side == 0, do: py + distance * ray_y, else: px + distance * ray_x
    fraction = hit - :math.floor(hit)

    fraction =
      if (side == 0 and ray_x > 0) or (side == 1 and ray_y < 0), do: 1 - fraction, else: fraction

    tile = context.atlas.tile

    texture =
      shaded(
        context,
        face(context, art, face_hit(side, ray_x, ray_y)),
        fog_level(context, distance),
        if(side == 0, do: 0.72, else: 1.0)
      )

    {:wall, distance, context.horizon - (from + storeys - context.eye) * scale,
     context.horizon - (from - context.eye) * scale, texture,
     fraction |> Kernel.*(tile) |> trunc() |> min(tile - 1), distance / context.vertical}
  end

  defp face_hit(0, ray_x, _ray_y), do: if(ray_x > 0, do: :west, else: :east)
  defp face_hit(1, _ray_x, ray_y), do: if(ray_y > 0, do: :north, else: :south)

  defp face(context, art, face) do
    entry = Atlas.entry(context.atlas, art)

    case Map.get(entry.faces, face) || Map.get(entry.faces, :side) do
      nil -> Atlas.frame_at(context.atlas, art, context.at)
      sprite -> sprite
    end
  end

  defp shaded(context, sprite, level, factor) do
    Canvas.memo(context.table, {:fp_shade, sprite.id, level, factor}, fn ->
      for <<pixel::binary-size(4) <- Raster.to_rgba_binary(sprite.raster)>>, into: <<>> do
        Canvas.shade(pixel, factor, context.atlas.void, level / @fog_levels)
      end
    end)
  end

  defp fog_level(context, distance),
    do: min(@fog_levels, trunc(distance / context.range * @fog_levels))

  defp standing_props(%{position: {px, py}, range: range} = context) do
    reach = ceil(range)

    for x <- (floor(px) - reach)..(floor(px) + reach)//1,
        y <- (floor(py) - reach)..(floor(py) + reach)//1,
        {_base, overlays, _tint} <- [context.cell.({x, y})],
        art <- overlays,
        Atlas.entry(context.atlas, art).height == 0,
        do: {art, {x + 0.5, y + 0.5}}
  end

  defp billboard(mover, columns, context, {dx, dy}, {px, py}, tan_half, width) do
    {art, {sx, sy}, heading} = with_heading(mover)
    {cx, cy} = context.position
    rel_x = sx - cx
    rel_y = sy - cy
    depth = rel_x * dx + rel_y * dy
    lateral = rel_x * px + rel_y * py

    if depth > 0.15 and abs(lateral) <= depth * tan_half + 1 do
      {pose, flip} = pose(heading, {rel_x, rel_y})
      sprite = Atlas.pose(context.atlas, art, pose, context.at)
      image = billboard_image(context, sprite, flip, fog_level(context, depth))
      tall = stand_tiles(context, art, image)
      place_billboard(columns, image, tall, context, {depth, lateral}, width)
    else
      columns
    end
  end

  defp stand_tiles(context, art, image) do
    case Atlas.entry(context.atlas, art).stand do
      nil -> image.height / context.atlas.tile
      stand -> stand
    end
  end

  defp place_billboard(columns, image, tall_tiles, context, {depth, lateral}, width) do
    scale = context.projection / depth * tall_tiles * image.width / image.height
    vertical = context.vertical / depth
    tall = vertical * tall_tiles
    left = width / 2 + lateral * context.projection / depth - scale / 2
    bottom = context.horizon + context.eye * vertical
    top = bottom - tall
    from = max(0, floor(left))
    to = min(width - 1, ceil(left + scale) - 1)

    Enum.reduce(from..to//1, columns, fn x, acc ->
      u = ((x + 0.5 - left) / scale * image.width) |> trunc() |> min(image.width - 1) |> max(0)
      span = {:sprite, depth, top, bottom, image.rgba, image.width, image.height, u, tall}
      Map.update!(acc, x, fn {spans, ray} -> {[span | spans], ray} end)
    end)
  end

  defp with_heading({art, position}), do: {art, position, nil}
  defp with_heading({art, position, heading}), do: {art, position, heading}

  defp pose(nil, _towards), do: {:front, false}

  defp pose(heading, {rel_x, rel_y}) do
    {hx, hy} = {:math.cos(heading), :math.sin(heading)}
    length = max(:math.sqrt(rel_x * rel_x + rel_y * rel_y), 1.0e-6)
    {tx, ty} = {-rel_x / length, -rel_y / length}
    dot = hx * tx + hy * ty
    cross = hx * ty - hy * tx

    cond do
      dot > 0.5 -> {:front, false}
      dot < -0.5 -> {:back, false}
      true -> {:side, cross < 0}
    end
  end

  defp billboard_image(context, sprite, flip, level) do
    Canvas.memo(context.table, {:fp_billboard, sprite.id, flip, level}, fn ->
      image = %{
        width: sprite.width,
        height: sprite.height,
        rgba: shaded(context, sprite, level, 1.0)
      }

      if flip, do: Canvas.flip(image), else: image
    end)
  end

  defp surface({spans, ray_x, ray_y}, y, context) do
    yc = y + 0.5

    case from_spans(spans, yc, context) do
      nil ->
        if yc <= context.horizon,
          do: {elem(context.sky, y), :infinity},
          else: floor_seen(ray_x, ray_y, yc, context)

      found ->
        found
    end
  end

  defp from_spans([], _yc, _context), do: nil

  defp from_spans([span | rest], yc, context) do
    if yc >= elem(span, 2) and yc <= elem(span, 3) do
      case span_pixel(span, yc, context) do
        <<_, _, _, alpha>> = found when alpha >= 128 -> {found, elem(span, 1)}
        _clear -> from_spans(rest, yc, context)
      end
    else
      from_spans(rest, yc, context)
    end
  end

  defp span_pixel({:wall, _distance, _top, _bottom, texture, u, factor}, yc, context) do
    tile = context.atlas.tile
    z = context.eye + (context.horizon - yc) * factor
    storey = trunc(z)
    row = tile - 1 - min(tile - 1, trunc((z - storey) * tile))
    binary_part(texture, (row * tile + u) * 4, 4)
  end

  defp span_pixel(
         {:sprite, _distance, top, _bottom, rgba, sprite_w, sprite_h, u, height_px},
         yc,
         _context
       ) do
    v = ((yc - top) / height_px * sprite_h) |> trunc() |> min(sprite_h - 1) |> max(0)
    binary_part(rgba, (v * sprite_w + u) * 4, 4)
  end

  defp floor_seen(ray_x, ray_y, yc, context) do
    {px, py} = context.position
    distance = context.eye * context.vertical / (yc - context.horizon)
    wx = px + ray_x * distance
    wy = py + ray_y * distance
    cx = :math.floor(wx)
    cy = :math.floor(wy)
    level = fog_level(context, min(distance, context.range))
    tile = context.atlas.tile

    case context.cell.({trunc(cx), trunc(cy)}) do
      :void ->
        {Map.fetch!(context.void, level), distance}

      {base, _overlays, _tint} ->
        texture = shaded(context, face(context, base, :top), level, 1.0)
        u = trunc((wx - cx) * tile)
        v = trunc((wy - cy) * tile)
        {binary_part(texture, (v * tile + u) * 4, 4), distance}
    end
  end
end
