defmodule Cauldron2D.Projection.Mode7 do
  @moduledoc """
  Composes the world as a ground plane seen in perspective from above it, turning freely:
  the floor recedes to a horizon, movers stand on it as billboards, and everything fades
  towards the atlas's void colour with distance.

      Cauldron2D.Projection.Mode7.render(:my_game,
        position: {12.5, 8.5},
        heading: :math.pi() / 2,
        cell: &MyGame.cell/1,
        size: {320, 200},
        movers: [{:hero, {14.5, 8.5}, 0.0}]
      )

  The plane is drawn from each cell's `:top` face, so a cell with storeys lies flat like
  any other: this projection has no verticality. Use `Cauldron2D.Projection.Iso`,
  `Cauldron2D.Projection.Oblique` or `Cauldron2D.Projection.FirstPerson` for a world
  whose walls must stand up.

  Unlike the isometric view the heading is continuous, so a game may turn by any angle.

  ## Options

    * `:position` — `{x, y}` in tiles, where the camera is, required
    * `:heading` — radians, `0` along `+x`, required
    * `:cell` — `fn {x, y} -> cell end`, as `Cauldron2D.Surface` takes cells; `:void` is
      drawn as the void colour, required
    * `:size` — `{width, height}` of the picture in pixels, required
    * `:eye` — how far above the plane the camera sits, in tiles. Default `1.6`
    * `:pitch` — `-0.8..0.8`, how far the horizon is moved down or up the picture.
      Default `0.0`
    * `:aspect` — a pixel's width over its height, so a picture drawn into cells that are
      not square keeps its proportions. Default `1.0`
    * `:fov` — the horizontal field of view in degrees. Default `70`
    * `:range` — how many tiles away the plane fades out entirely. Default `24`
    * `:sky` — `{top, bottom}` colours above the horizon. Default a blue gradient
    * `:movers` — `[{art, {x, y}}]` or `[{art, {x, y}, heading}]`; a mover shows its
      `:front` pose when heading towards the camera, `:back` away, `:side` across
      (mirrored one way); with no heading it faces the camera. Default `[]`
    * `:volumes` — coloured regions of space, as `Cauldron2D.Projection.Volume`
      describes them, each tinting the plane and the movers behind it. Default `[]`
    * `:at` — the time in milliseconds an animated art's frame is chosen for. Default `0`
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{Canvas, Ground, Volume}
  alias FrenchCurve.Raster

  @fog_levels 6
  @near 0.2
  @default_sky {{24, 30, 58}, {96, 120, 170}}

  @type option ::
          {:position, {number(), number()}}
          | {:heading, number()}
          | {:cell, ({integer(), integer()} -> Cauldron2D.Surface.cell())}
          | {:size, {pos_integer(), pos_integer()}}
          | {:eye, number()}
          | {:pitch, number()}
          | {:aspect, number()}
          | {:fov, number()}
          | {:range, number()}
          | {:sky, {{byte(), byte(), byte()}, {byte(), byte(), byte()}}}
          | {:movers, [tuple()]}
          | {:volumes, [map()]}
          | {:at, integer()}

  @doc "The picture, as the module documentation describes."
  @spec render(Atlas.name() | Atlas.t(), [option()]) :: Raster.t()
  def render(atlas, opts) do
    atlas = Atlas.fetch(atlas)
    context = context(atlas, opts)
    {width, height} = context.size

    rows =
      Ground.rows(%{
        grid: grid(context, atlas),
        size: context.size,
        tile: atlas.tile,
        camera: camera(context),
        void: atlas.void,
        levels: @fog_levels,
        sky: context.sky
      })

    boards =
      opts
      |> Keyword.get(:movers, [])
      |> Enum.map(&billboard(&1, context, atlas))
      |> Enum.reject(&is_nil/1)

    (boards ++ volume_items(opts, context))
    |> Enum.sort_by(& &1.depth, :desc)
    |> Enum.reduce(%{width: width, height: height, rows: rows}, &painted(&2, &1))
    |> Canvas.to_raster()
  end

  defp painted(canvas, %{paint: paint}), do: paint.(canvas)
  defp painted(canvas, board), do: paint_billboard(canvas, board)

  defp volume_items(opts, context) do
    for volume <- Volume.list(Keyword.get(opts, :volumes, [])) do
      {depth, _lateral} = camera_space(context, volume.at)
      %{depth: depth, paint: &volume(&1, volume, context)}
    end
  end

  defp volume(canvas, volume, context) do
    {fx, fy} = context.position
    plan = Volume.eye_plan({fx, fy, context.eye}, &looking(&1, context))

    Volume.paint(canvas, volume, volume_box(volume, context), plan)
  end

  defp looking({px, py}, context) do
    {dx, dy} = context.direction
    {rx, ry} = context.right
    {width, _height} = context.size
    side = (px - width / 2) / context.projection

    {dx + rx * side, dy + ry * side, (context.horizon - py) / context.vertical}
  end

  defp volume_box(volume, context) do
    {depth, _lateral} = camera_space(context, volume.at)

    if depth - Volume.reach(volume) < @near do
      {width, height} = context.size
      {0, 0, width - 1, height - 1}
    else
      Volume.box(volume, &screen_point(&1, context))
    end
  end

  defp screen_point({x, y, z}, context) do
    {depth, lateral} = camera_space(context, {x, y})

    if depth > @near do
      {width, _height} = context.size

      {width / 2 + lateral * context.projection / depth,
       context.horizon + (context.eye - z) * context.vertical / depth}
    end
  end

  defp camera(context) do
    {fx, fy} = context.position
    {dx, dy} = context.direction
    {rx, ry} = context.right

    {fx / 1, fy / 1, dx / 1, dy / 1, rx / 1, ry / 1, context.horizon / 1, context.projection / 1,
     context.vertical / 1, context.eye / 1, context.range / 1}
  end

  defp grid(context, atlas) do
    {fx, fy} = context.position
    reach = ceil(context.range) + 2
    {left, top} = {floor(fx) - reach, floor(fy) - reach}
    {arts, textures} = plane_textures(context, atlas)

    {cells, bounds} =
      Ground.build_grid(context.cell, {left, top, left + 2 * reach, top + 2 * reach}, arts)

    %{cells: cells, bounds: bounds, textures: textures}
  end

  defp plane_textures(context, atlas) do
    arts = atlas |> Atlas.arts() |> Enum.sort()
    sprites = Enum.map(arts, &top_sprite(context, &1))
    slot = atlas.tile * atlas.tile * 4
    build = fn -> for sprite <- sprites, into: <<>>, do: fitted(sprite, slot) end

    textures =
      if context.table,
        do: Canvas.memo(context.table, {:plane, Enum.map(sprites, & &1.id)}, build),
        else: build.()

    {Map.new(Enum.with_index(arts, 1)), textures}
  end

  defp fitted(sprite, slot) do
    rgba = Raster.to_rgba_binary(sprite.raster)

    case byte_size(rgba) do
      size when size >= slot -> binary_part(rgba, 0, slot)
      size -> rgba <> :binary.copy(<<0, 0, 0, 0>>, div(slot - size, 4))
    end
  end

  defp paint_billboard(canvas, board) do
    left = round(board.left)
    top = round(board.top)
    size = {max(1, round(board.wide)), max(1, round(board.tall))}
    window = window(size, {left, top}, canvas)

    case window do
      nil ->
        canvas

      {x0, y0, _x1, _y1} = window ->
        stamp = Canvas.stamp(stretched(board.image, size, window))
        Canvas.paint(canvas, stamp, {left + x0, top + y0})
    end
  end

  defp window({wide, tall}, {left, top}, %{width: width, height: height}) do
    x0 = max(0, -left)
    y0 = max(0, -top)
    x1 = min(wide, width - left)
    y1 = min(tall, height - top)

    if x1 > x0 and y1 > y0, do: {x0, y0, x1, y1}
  end

  defp stretched(%{width: width, height: height, rgba: rgba}, {wide, tall}, {x0, y0, x1, y1}) do
    columns = for x <- x0..(x1 - 1)//1, do: min(width - 1, trunc(x * width / wide))

    pixels =
      for y <- y0..(y1 - 1)//1, into: <<>> do
        row = min(height - 1, trunc(y * height / tall)) * width

        for column <- columns, into: <<>>, do: binary_part(rgba, (row + column) * 4, 4)
      end

    %{width: x1 - x0, height: y1 - y0, rgba: pixels}
  end

  @doc "Where world point `{x, y}` lands in the picture, or `nil` when it is behind the camera."
  @spec project(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) ::
          {float(), float()} | nil
  def project(atlas, point, opts) do
    context = context(Atlas.fetch(atlas), opts)
    {depth, lateral} = camera_space(context, point)

    if depth > 0.01 do
      {width, _} = context.size

      {width / 2 + lateral * context.projection / depth,
       context.horizon + context.eye * context.vertical / depth}
    end
  end

  @doc "The world point under picture pixel `{px, py}`, or `nil` at or above the horizon."
  @spec unproject(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) ::
          {float(), float()} | nil
  def unproject(atlas, {px, py}, opts) do
    context = context(Atlas.fetch(atlas), opts)

    if py > context.horizon do
      {width, _} = context.size
      depth = context.eye * context.vertical / (py - context.horizon)
      lateral = (px - width / 2) * depth / context.projection
      {fx, fy} = context.position
      {dx, dy} = context.direction
      {rx, ry} = context.right
      {fx + dx * depth + rx * lateral, fy + dy * depth + ry * lateral}
    end
  end

  @doc "The tile under picture pixel `{px, py}`, or `nil` at or above the horizon."
  @spec tile_at(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) ::
          {integer(), integer()} | nil
  def tile_at(atlas, point, opts) do
    case unproject(atlas, point, opts) do
      nil -> nil
      {x, y} -> {floor(x), floor(y)}
    end
  end

  defp context(atlas, opts) do
    {width, height} = Keyword.fetch!(opts, :size)
    heading = Keyword.fetch!(opts, :heading)
    pitch = opts |> Keyword.get(:pitch, 0.0) |> min(0.8) |> max(-0.8)
    fov = Keyword.get(opts, :fov, 70) * :math.pi() / 180
    projection = width / 2 / :math.tan(fov / 2)

    %{
      atlas: atlas,
      table: atlas.name && Atlas.cache(atlas.name),
      cell: Keyword.get(opts, :cell),
      at: Keyword.get(opts, :at, 0),
      size: {width, height},
      horizon: height / 2 + pitch * height / 2,
      projection: projection,
      vertical: projection / Keyword.get(opts, :aspect, 1.0),
      position: Keyword.fetch!(opts, :position),
      direction: {:math.cos(heading), :math.sin(heading)},
      right: {-:math.sin(heading), :math.cos(heading)},
      eye: Keyword.get(opts, :eye, 1.6) / 1,
      range: Keyword.get(opts, :range, 24) / 1,
      sky: sky(height, height / 2 + pitch * height / 2, Keyword.get(opts, :sky, @default_sky))
    }
  end

  defp camera_space(context, {x, y}) do
    {cx, cy} = context.position
    {dx, dy} = context.direction
    {rx, ry} = context.right
    {(x - cx) * dx + (y - cy) * dy, (x - cx) * rx + (y - cy) * ry}
  end

  defp sky(height, horizon, {{tr, tg, tb}, {br, bg, bb}}) do
    for y <- 0..(height - 1)//1 do
      mix = min(1.0, y / max(horizon, 1))

      <<round(tr + (br - tr) * mix), round(tg + (bg - tg) * mix), round(tb + (bb - tb) * mix),
        255>>
    end
    |> List.to_tuple()
  end

  defp fog_level(context, depth),
    do: min(@fog_levels, trunc(max(depth, 0) / context.range * @fog_levels))

  defp billboard(mover, context, atlas) do
    {art, {x, y}, heading} = with_heading(mover)
    {depth, lateral} = camera_space(context, {x, y})

    if depth > 0.2 and depth < context.range do
      {pose, flip} = pose(heading, context)
      sprite = Atlas.pose(atlas, art, pose, context.at)
      stand = Atlas.entry(atlas, art).stand || sprite.height / atlas.tile
      image = shaded(context, sprite, flip, fog_level(context, depth))

      {width, _} = context.size
      vertical = context.vertical / depth
      tall = vertical * stand
      wide = tall * sprite.width / sprite.height
      ground = context.horizon + context.eye * vertical

      %{
        depth: depth,
        left: width / 2 + lateral * context.projection / depth - wide / 2,
        top: ground - tall,
        wide: wide,
        tall: tall,
        image: image
      }
    end
  end

  defp with_heading({art, position}), do: {art, position, nil}
  defp with_heading({art, position, heading}), do: {art, position, heading}

  defp pose(nil, _context), do: {:front, false}

  defp pose(heading, context) do
    {hx, hy} = {:math.cos(heading), :math.sin(heading)}
    {dx, dy} = context.direction
    dot = hx * dx + hy * dy
    cross = hx * dy - hy * dx

    cond do
      dot < -0.5 -> {:front, false}
      dot > 0.5 -> {:back, false}
      true -> {:side, cross > 0}
    end
  end

  defp shaded(context, sprite, flip, level) do
    build = fn ->
      rgba =
        for <<pixel::binary-size(4) <- Raster.to_rgba_binary(sprite.raster)>>, into: <<>> do
          Canvas.shade(pixel, 1.0, context.atlas.void, level / @fog_levels)
        end

      image = %{width: sprite.width, height: sprite.height, rgba: rgba}
      if flip, do: Canvas.flip(image), else: image
    end

    if context.table,
      do: Canvas.memo(context.table, {:mode7, sprite.id, flip, level}, build),
      else: build.()
  end

  defp top_sprite(context, art) do
    entry = Atlas.entry(context.atlas, art)
    Map.get(entry.faces, :top) || Atlas.frame_at(context.atlas, art, context.at)
  end
end
