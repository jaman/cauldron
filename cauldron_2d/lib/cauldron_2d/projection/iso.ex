defmodule Cauldron2D.Projection.Iso do
  @moduledoc """
  Composes a view of the world as an isometric picture: floors as diamonds, standing
  arts as blocks with a top and two shaded sides, movers and flat overlays as upright
  sprites, painted back to front.

      Cauldron2D.Projection.Iso.compose(:my_game,
        focus: {12.5, 8.5},
        cell: &MyGame.cell/1,
        size: {320, 200},
        facing: 1,
        movers: [{:hero, {12.5, 8.5}, heading}]
      )

  A tile of `t` pixels is drawn as a diamond `2t` wide and `t * tilt` tall, rounded to an
  even number of pixels so neighbouring diamonds meet, and a storey is `t` tall. The
  focus sits at the centre of the picture. `facing` turns the world a quarter turn at a
  time by default: at facing `0` world `+x` runs down-right and `+y` down-left.
  `facings` makes a turn out of more steps than four.

  Up to `32` facings the view is blitted from stamps, one set per art per facing, built
  on first use and kept in the atlas cache; a `:facing` between two steps is drawn at the
  nearer. Above `32`, and with `facings: :free`, the ground and the standing arts are
  sampled a pixel at a time instead, which turns to any angle at all and costs upwards of
  fifteen times as much a frame.

  ## Options

    * `:focus` — `{x, y}` in tiles, the world point at the picture's centre, required
    * `:cell` — `fn {x, y} -> cell end`, as `Cauldron2D.Surface` takes cells, required
    * `:size` — `{width, height}` of the picture in pixels, required
    * `:facing` — which step of a turn the view is at, `0` to `facings - 1`, clockwise.
      A fraction is drawn at the nearer step, unless the view samples, where it turns by
      part of a step. Default `0`
    * `:facings` — how many steps make a full turn, at least `4`; `:free` for a view that
      turns to any angle. Up to `32` the view is stamped, above it sampled. Default `4`
    * `:tilt` — the diamond's height as a fraction of the tile size, `0.5..1.5`.
      Default `1.0`, a 2:1 diamond
    * `:shrink` — `1`, `2` or `4`; the whole picture at that fraction of its size, so
      the same pixels show that many more tiles. Default `1`
    * `:movers` — `[{art, {x, y}}]` or `[{art, {x, y}, heading}]` in tiles, `heading` in
      radians with `0` along `+x`. A mover shows its `:front` pose when heading
      towards the camera and `:back` when away, mirrored when heading left; with no
      heading it faces the camera. Default `[]`
    * `:labels` — `[{text, {x, y}, colour}]` or with a fourth element of options as
      `Cauldron2D.Surface.compose/4` takes them, positioned by the tile. Default `[]`
    * `:volumes` — coloured regions of space, as `Cauldron2D.Projection.Volume`
      describes them, each tinting what is drawn behind it. Default `[]`
    * `:at` — the time in milliseconds an animated art's frame is chosen for. Default `0`

  `project/2`, `unproject/2` and `tile_at/2` map between picture pixels and world tiles
  for the same options.
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{Canvas, Volume}
  alias FrenchCurve.Raster

  @left_shade 0.62
  @right_shade 0.82
  @stamped_facings 32
  @seam 1.0
  @spread 1.0
  @storeys 4

  @type option ::
          {:focus, {number(), number()}}
          | {:cell, ({integer(), integer()} -> Cauldron2D.Surface.cell())}
          | {:size, {pos_integer(), pos_integer()}}
          | {:facing, 0..3}
          | {:tilt, number()}
          | {:shrink, 1 | 2 | 4}
          | {:movers, [tuple()]}
          | {:labels, [tuple()]}
          | {:volumes, [map()]}
          | {:at, integer()}

  @doc "The picture, as the module documentation describes."
  @spec compose(Atlas.name() | Atlas.t(), [option()]) :: Raster.t()
  def compose(atlas, opts) do
    atlas = Atlas.fetch(atlas)
    geometry = geometry(atlas, opts)

    if geometry.stamps?,
      do: stamped(atlas, geometry, opts),
      else: sampled(atlas, geometry, opts)
  end

  defp stamped(atlas, geometry, opts) do
    {width, height} = geometry.size
    cell = Keyword.fetch!(opts, :cell)
    at = Keyword.get(opts, :at, 0)

    cells = visible_cells(cell, geometry)

    canvas =
      Enum.reduce(cells, Canvas.new(width, height, atlas.void), fn {position, tile}, acc ->
        floor(acc, atlas, position, tile, geometry, at)
      end)

    items =
      standing_items(atlas, cells, geometry, at) ++
        mover_items(atlas, Keyword.get(opts, :movers, []), geometry, at) ++
        volume_items(opts, geometry)

    canvas = items |> Enum.sort_by(& &1.depth) |> Enum.reduce(canvas, &painted/2)

    Keyword.get(opts, :labels, [])
    |> Enum.reduce(canvas, &label(&2, &1, geometry))
    |> Canvas.to_raster()
  end

  defp sampled(atlas, geometry, opts) do
    cell = Keyword.fetch!(opts, :cell)
    at = Keyword.get(opts, :at, 0)
    cells = visible_cells(cell, geometry)

    items =
      standing_blocks(atlas, cells, geometry, at) ++
        walking_movers(atlas, Keyword.get(opts, :movers, []), geometry, at) ++
        volume_items(opts, geometry)

    canvas =
      items
      |> Enum.sort_by(& &1.depth)
      |> Enum.reduce(ground(geometry, atlas, cell, at), &painted/2)

    opts
    |> Keyword.get(:labels, [])
    |> Enum.reduce(canvas, &label(&2, &1, geometry))
    |> Canvas.to_raster()
  end

  defp painted(%{stamps: stamps}, canvas),
    do: Enum.reduce(stamps, canvas, fn {stamp, at}, acc -> Canvas.paint(acc, stamp, at) end)

  defp painted(%{paint: paint}, canvas), do: paint.(canvas)

  defp volume_items(opts, geometry) do
    for volume <- Volume.list(Keyword.get(opts, :volumes, [])) do
      %{depth: depth_of(volume.at, geometry), paint: &volume(&1, volume, geometry)}
    end
  end

  defp volume(canvas, volume, geometry) do
    direction = Volume.eyeline(geometry.across, geometry.down, geometry.block_h)
    plan = Volume.ground_plan(&unprojected(&1, geometry), direction)

    Volume.paint(canvas, volume, Volume.box(volume, &solid(&1, geometry)), plan)
  end

  defp solid({x, y, z}, geometry), do: raised(place({x, y}, geometry), z * geometry.block_h)

  defp ground(geometry, atlas, cell, at) do
    {width, height} = geometry.size
    {_cx, cy} = geometry.centre

    {rows, _textures} =
      Enum.map_reduce(0..(height - 1)//1, %{}, fn py, textures ->
        {pixels, textures} =
          ground_row(geometry, atlas, cell, at, (py + 0.5 - cy) / geometry.half_h, textures)

        {{py, pixels}, textures}
      end)

    %{width: width, height: height, rows: Map.new(rows)}
  end

  defp ground_row(geometry, atlas, cell, at, v, textures) do
    {width, _height} = geometry.size
    {cx, _cy} = geometry.centre
    {fx, fy} = geometry.focus

    {pixels, textures} =
      Enum.map_reduce(0..(width - 1)//1, textures, fn px, acc ->
        u = (px + 0.5 - cx) / geometry.half_w
        {dx, dy} = unrotate({(u + v) / 2, (v - u) / 2}, geometry)
        point = {fx + dx, fy + dy}
        ground_pixel(cell.(tile_of(point)), point, atlas, at, acc)
      end)

    {IO.iodata_to_binary(pixels), textures}
  end

  defp tile_of({wx, wy}), do: {floor(wx), floor(wy)}

  defp ground_pixel(:void, _point, atlas, _at, textures), do: {void_pixel(atlas), textures}

  defp ground_pixel({base, _overlays, tint}, {wx, wy}, atlas, at, textures) do
    key = {base, tint}

    textures =
      Map.put_new_lazy(textures, key, fn ->
        tinted(atlas, face_at(atlas, base, :top, at), tint)
      end)

    texel =
      Canvas.texel(
        Map.fetch!(textures, key),
        atlas.tile,
        wx - :math.floor(wx),
        wy - :math.floor(wy)
      )

    {texel, textures}
  end

  defp void_pixel(%{void: {red, green, blue}}), do: <<red, green, blue, 255>>

  defp standing_blocks(atlas, cells, geometry, at) do
    for {position, {base, overlays, tint}} <- cells,
        arts = for(art <- [base | overlays], Atlas.entry(atlas, art).height > 0, do: art),
        arts != [] do
      %{
        depth: depth_of(centre_of(position), geometry),
        paint: &stack_blocks(&1, atlas, arts, tint, position, geometry, at)
      }
    end
  end

  defp stack_blocks(canvas, atlas, arts, tint, position, geometry, at) do
    arts
    |> Enum.reduce({canvas, 0}, fn art, {painted, storeys} ->
      height = Atlas.entry(atlas, art).height
      {block(painted, atlas, art, tint, position, storeys, geometry, at), storeys + height}
    end)
    |> elem(0)
  end

  defp centre_of({x, y}), do: {x + 0.5, y + 0.5}

  defp block(canvas, atlas, art, tint, {x, y}, storeys, geometry, at) do
    height = Atlas.entry(atlas, art).height
    base = storeys * geometry.block_h
    top = base + height * geometry.block_h

    canvas
    |> sides(atlas, art, tint, {x, y}, {base, top}, geometry, at)
    |> cap(atlas, art, tint, {x, y}, top, geometry, at)
  end

  defp cap(canvas, atlas, art, tint, {x, y}, lift, geometry, at) do
    texture = tinted(atlas, face_at(atlas, art, :top, at), tint)
    tile = atlas.tile
    {ox, oy} = raised(place({x, y}, geometry), lift)
    {ax, ay} = raised(place({x + 1, y}, geometry), lift)
    {dx, dy} = raised(place({x, y + 1}, geometry), lift)

    Canvas.quad(canvas, {ox, oy}, {ax - ox, ay - oy}, {dx - ox, dy - oy}, fn u, v ->
      Canvas.texel(texture, tile, u, v)
    end)
  end

  defp raised({sx, sy}, lift), do: {sx, sy - lift}

  @faces [
    {:east, {1, 0}, {1, 0}, {1, 1}},
    {:west, {-1, 0}, {0, 1}, {0, 0}},
    {:south, {0, 1}, {1, 1}, {0, 1}},
    {:north, {0, -1}, {0, 0}, {1, 0}}
  ]

  defp sides(canvas, atlas, art, tint, position, {base, top}, geometry, at) do
    block = %{
      atlas: atlas,
      art: art,
      tint: tint,
      position: position,
      base: base,
      top: top,
      height: Atlas.entry(atlas, art).height,
      tile: atlas.tile,
      at: at
    }

    Enum.reduce(@faces, canvas, &side(&2, block, &1, geometry))
  end

  defp side(canvas, block, {name, normal, from, to}, geometry) do
    case screen_normal(normal, geometry) do
      {_nx, ny} when ny <= 0 ->
        canvas

      _towards_viewer ->
        texture = tinted(block.atlas, face_at(block.atlas, block.art, name, block.at), block.tint)
        shade = face_shade(normal, geometry)
        {sx, sy} = raised(place(corner(block.position, from), geometry), block.top)
        {ex, ey} = raised(place(corner(block.position, to), geometry), block.top)

        Canvas.quad(canvas, {sx, sy}, {ex - sx, ey - sy}, {0, block.top - block.base}, fn u, v ->
          texel = Canvas.texel(texture, block.tile, u, rem_one(v * block.height))
          Canvas.shade(texel, shade, {0, 0, 0}, 0)
        end)
    end
  end

  defp corner({x, y}, {dx, dy}), do: {x + dx, y + dy}

  defp rem_one(value), do: value - :math.floor(value)

  defp screen_normal({nx, ny}, geometry) do
    {rx, ry} = rotate({nx, ny}, geometry)
    {(rx - ry) * geometry.half_w, (rx + ry) * geometry.half_h}
  end

  defp face_shade(normal, geometry) do
    {nx, _ny} = screen_normal(normal, geometry)
    reach = geometry.half_w * 1.5
    mix = (nx / reach + 1) / 2
    @left_shade + (@right_shade - @left_shade) * min(1.0, max(0.0, mix))
  end

  defp walking_movers(atlas, movers, geometry, at) do
    for mover <- movers do
      {_art, position, _heading} = walker = with_heading(mover)
      %{depth: depth_of(position, geometry), paint: &place_mover(&1, atlas, walker, geometry, at)}
    end
  end

  defp place_mover(canvas, atlas, {art, {x, y}, heading}, geometry, at) do
    {pose, flip} = pose(heading, geometry)
    sprite = Atlas.pose(atlas, art, pose, at)

    stamp =
      stamp(atlas, {:upright, sprite.id, nil, flip}, geometry, fn ->
        upright(atlas, sprite, nil, flip)
      end)

    {stamp, at_px} = standing(stamp, place({x, y}, geometry), geometry)
    Canvas.paint(canvas, stamp, at_px)
  end

  @doc "Where world point `{x, y}` lands in the picture, in pixels from its top-left corner."
  @spec project(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) :: {float(), float()}
  def project(atlas, point, opts), do: place(point, geometry(Atlas.fetch(atlas), opts))

  defp place({x, y}, geometry) do
    {fx, fy} = geometry.focus
    {rx, ry} = rotate({x - fx, y - fy}, geometry)
    {cx, cy} = geometry.centre
    {cx + (rx - ry) * geometry.half_w, cy + (rx + ry) * geometry.half_h}
  end

  @doc "The world point under picture pixel `{px, py}`, on the ground."
  @spec unproject(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) ::
          {float(), float()}
  def unproject(atlas, pixel, opts), do: unprojected(pixel, geometry(Atlas.fetch(atlas), opts))

  defp unprojected({px, py}, geometry) do
    {cx, cy} = geometry.centre
    u = (px - cx) / geometry.half_w
    v = (py - cy) / geometry.half_h
    {dx, dy} = unrotate({(u + v) / 2, (v - u) / 2}, geometry)
    {fx, fy} = geometry.focus
    {fx + dx, fy + dy}
  end

  @doc """
  The heading in radians, `0` along `+x`, a game walks for the `:up` action at the
  `:facing` and `:facings` given, so that pressing up moves the same way across the
  picture however far the view has turned. `:down` is against it and `:left` and
  `:right` across it.

      Cauldron2D.Projection.Iso.up(facing: 5, facings: 16)
  """
  @spec up([option()]) :: float()
  def up(opts) do
    {_facing, _facings, angle} = turn(opts)
    :math.atan2(-:math.cos(angle), :math.sin(angle))
  end

  @doc """
  The ground as a straight walk across the picture: `{origin, across, down}`, the world
  point at the top-left pixel and the world it moves one pixel right and one pixel down.

  The ground map is exact, so `origin + px * across + py * down` is the world point
  `unproject/3` answers for `{px, py}`. A caller drawing a grid can take the map once and
  add.
  """
  @spec ground_map(Atlas.name() | Atlas.t(), [option()]) ::
          {{float(), float()}, {float(), float()}, {float(), float()}}
  def ground_map(atlas, opts), do: walked(geometry(Atlas.fetch(atlas), opts), &unprojected/2)

  @doc """
  The cells this picture shows, each as `{position, tile}` with the tile the `:cell`
  function gave for it.

  Cells the function answered `:void` for are left out, and so is everything outside the
  picture.
  """
  @spec cells(Atlas.name() | Atlas.t(), [option()]) :: [{{integer(), integer()}, term()}]
  def cells(atlas, opts),
    do: visible_cells(Keyword.fetch!(opts, :cell), geometry(Atlas.fetch(atlas), opts))

  @doc "The tile under picture pixel `{px, py}`."
  @spec tile_at(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) ::
          {integer(), integer()}
  def tile_at(atlas, pixel, opts) do
    {x, y} = unproject(atlas, pixel, opts)
    {floor(x), floor(y)}
  end

  defp walked(geometry, at) do
    {ox, oy} = origin = at.({0, 0}, geometry)
    {rx, ry} = at.({1, 0}, geometry)
    {dx, dy} = at.({0, 1}, geometry)

    {origin, {rx - ox, ry - oy}, {dx - ox, dy - oy}}
  end

  defp geometry(atlas, opts) do
    tile = atlas.tile
    shrink = Keyword.get(opts, :shrink, 1)
    tilt = opts |> Keyword.get(:tilt, 1.0) |> min(1.5) |> max(0.5)
    tile_h = max(2, 2 * round(tile * tilt / 2))
    {width, height} = Keyword.fetch!(opts, :size)
    {facing, facings, angle} = turn(opts)

    %{
      tile: tile,
      shrink: shrink,
      tilt: tilt,
      tile_w: 2 * tile / shrink,
      half_w: tile / shrink,
      tile_h: tile_h / shrink,
      half_h: tile_h / 2 / shrink,
      block_h: tile / shrink,
      stamp_tile_h: tile_h,
      facing: facing,
      facings: facings,
      angle: angle,
      cos: :math.cos(angle),
      sin: :math.sin(angle),
      stepped?: facings == 4,
      stamps?: facings <= @stamped_facings,
      across: edge({1, 0}, angle, tile / shrink, tile_h / 2 / shrink),
      down: edge({0, 1}, angle, tile / shrink, tile_h / 2 / shrink),
      focus: Keyword.fetch!(opts, :focus),
      size: {width, height},
      centre: {width / 2, height / 2}
    }
  end

  defp edge({dx, dy}, angle, half_w, half_h) do
    c = :math.cos(angle)
    s = :math.sin(angle)
    {rx, ry} = {dx * c + dy * s, dy * c - dx * s}
    {(rx - ry) * half_w, (rx + ry) * half_h}
  end

  defp turn(opts) do
    facings =
      opts |> Keyword.get(:facings, 4) |> then(&if(&1 == :free, do: 360, else: &1)) |> max(4)

    facing = opts |> Keyword.get(:facing, 0) |> snapped(facings)
    {facing, facings, facing * 2 * :math.pi() / facings}
  end

  defp snapped(facing, facings) when facings > @stamped_facings, do: facing

  defp snapped(facing, facings) when is_integer(facing), do: Integer.mod(facing, facings)

  defp snapped(facing, facings), do: facing |> round() |> Integer.mod(facings)

  defp rotate({dx, dy}, %{stepped?: true, facing: facing}), do: quarter({dx, dy}, facing)
  defp rotate({dx, dy}, %{cos: c, sin: s}), do: {dx * c + dy * s, dy * c - dx * s}

  defp unrotate(point, %{stepped?: true, facing: facing}),
    do: quarter(point, rem(4 - facing, 4))

  defp unrotate({dx, dy}, %{cos: c, sin: s}), do: {dx * c - dy * s, dy * c + dx * s}

  defp quarter({dx, dy}, 0), do: {dx, dy}
  defp quarter({dx, dy}, 1), do: {dy, -dx}
  defp quarter({dx, dy}, 2), do: {-dx, -dy}
  defp quarter({dx, dy}, 3), do: {-dy, dx}

  defp visible_cells(cell, geometry) do
    {left, top, right, bottom} = world_bounds(geometry)

    for x <- left..right//1,
        y <- top..bottom//1,
        on_screen?({x, y}, geometry),
        tile = cell.({x, y}),
        tile != :void,
        do: {{x, y}, tile}
  end

  defp world_bounds(geometry) do
    {width, height} = geometry.size
    rise = @storeys * geometry.block_h

    corners =
      for px <- [0, width], py <- [-rise, height + rise], do: unprojected({px, py}, geometry)

    xs = Enum.map(corners, &elem(&1, 0))
    ys = Enum.map(corners, &elem(&1, 1))

    {Kernel.floor(Enum.min(xs)) - 1, Kernel.floor(Enum.min(ys)) - 1, ceil(Enum.max(xs)) + 1,
     ceil(Enum.max(ys)) + 1}
  end

  defp on_screen?(position, geometry) do
    {width, height} = geometry.size
    {px, py} = place(position, geometry)
    {ax, ay} = geometry.across
    {bx, by} = geometry.down
    xs = [0, ax, bx, ax + bx]
    ys = [0, ay, by, ay + by]

    px + Enum.max(xs) > -@seam and px + Enum.min(xs) < width + @seam and
      py + Enum.max(ys) > -@seam and
      py + Enum.min(ys) - @storeys * geometry.block_h < height + @seam
  end

  defp depth_of({x, y}, geometry) do
    {fx, fy} = geometry.focus
    {rx, ry} = rotate({x - fx, y - fy}, geometry)
    rx + ry
  end

  defp floor(canvas, atlas, position, {base, _overlays, tint}, geometry, at) do
    top = face_at(atlas, base, :top, at)

    %{stamp: stamp, offset: {left, above}} =
      turned(atlas, {:tile, top.id, tint}, geometry, fn ->
        tile_image(atlas, top, tint, geometry)
      end)

    {px, py} = place(position, geometry)
    Canvas.paint(canvas, stamp, {round(px + left), round(py + above)})
  end

  defp tile_image(atlas, top, tint, geometry) do
    texture = tinted(atlas, top, tint)
    tile = geometry.tile
    {across, down, origin} = grown(geometry.across, geometry.down)
    drawn([{origin, across, down, fn u, v -> Canvas.texel(texture, tile, u, v) end}])
  end

  defp block_image(atlas, faces, cap, tint, geometry) do
    tile = geometry.tile
    lift = geometry.block_h
    texture = tinted(atlas, cap, tint)
    {across, down, origin} = grown(geometry.across, geometry.down)

    sides =
      for {sprite, normal, from, to} <- faces,
          quad =
            side_quad(
              tinted(atlas, sprite, tint),
              face_shade(normal, geometry),
              {from, to},
              geometry
            ),
          quad != nil,
          do: quad

    drawn(
      sides ++
        [{raised(origin, lift), across, down, fn u, v -> Canvas.texel(texture, tile, u, v) end}]
    )
  end

  defp side_quad(texture, shade, {from, to}, geometry) do
    lift = geometry.block_h
    tile = geometry.tile
    {sx, sy} = corner_at(from, geometry)
    {ex, ey} = corner_at(to, geometry)

    if abs(ex - sx) < 1 do
      nil
    else
      {along, downward, {gx, gy}} = grown({ex - sx, ey - sy}, {0, lift})

      {{sx + gx, sy - lift + gy}, along, downward,
       fn u, v -> Canvas.shade(Canvas.texel(texture, tile, u, v), shade, {0, 0, 0}, 0) end}
    end
  end

  defp corner_at({dx, dy}, %{across: {ax, ay}, down: {bx, by}}),
    do: {dx * ax + dy * bx, dx * ay + dy * by}

  defp grown({ax, ay}, {bx, by}) do
    span = abs(ax * by - ay * bx)
    a = :math.sqrt(ax * ax + ay * ay)
    b = :math.sqrt(bx * bx + by * by)
    out_a = min(@seam * b / max(span, 1.0e-9), @spread)
    out_b = min(@seam * a / max(span, 1.0e-9), @spread)

    {{ax * (1 + 2 * out_a), ay * (1 + 2 * out_a)}, {bx * (1 + 2 * out_b), by * (1 + 2 * out_b)},
     {-ax * out_a - bx * out_b, -ay * out_a - by * out_b}}
  end

  defp drawn(quads) do
    corners =
      for {{ox, oy}, {ax, ay}, {bx, by}, _texel} <- quads,
          point <- [
            {ox, oy},
            {ox + ax, oy + ay},
            {ox + bx, oy + by},
            {ox + ax + bx, oy + ay + by}
          ],
          do: point

    xs = Enum.map(corners, &elem(&1, 0))
    ys = Enum.map(corners, &elem(&1, 1))
    left = xs |> Enum.min() |> Kernel.floor()
    above = ys |> Enum.min() |> Kernel.floor()
    blank = Canvas.blank(ceil(Enum.max(xs)) - left + 1, ceil(Enum.max(ys)) - above + 1)

    canvas =
      Enum.reduce(quads, blank, fn {{ox, oy}, across, down, texel}, acc ->
        Canvas.quad(acc, {ox - left, oy - above}, across, down, texel)
      end)

    %{offset: {left, above}, image: Canvas.to_image(canvas)}
  end

  defp standing_items(atlas, cells, geometry, at) do
    for {position, {base, overlays, tint}} <- cells,
        arts =
          for(
            art <- [base | overlays],
            Atlas.entry(atlas, art).height > 0 or art != base,
            do: art
          ),
        arts != [] do
      {stamps, _storeys} =
        Enum.reduce(arts, {[], 0}, &stack(atlas, &1, tint, position, geometry, at, &2))

      %{depth: depth_of(centre_of(position), geometry), stamps: stamps}
    end
  end

  defp stack(atlas, art, tint, position, geometry, at, {stamps, storeys}) do
    case Atlas.entry(atlas, art) do
      %{height: 0} ->
        stamp =
          stamp(atlas, {:upright, Atlas.frame_at(atlas, art, at).id, tint, false}, geometry, fn ->
            upright(atlas, Atlas.frame_at(atlas, art, at), tint, false)
          end)

        foot = place(centre_of(position), geometry)
        {stamps ++ [standing(stamp, foot, geometry)], storeys}

      %{height: height} ->
        cap = face_at(atlas, art, :top, at)
        faces = facing_sides(atlas, art, at, geometry)

        %{stamp: cube, offset: {left, above}} =
          turned(atlas, {:block, cap.id, Enum.map(faces, &elem(&1, 0).id), tint}, geometry, fn ->
            block_image(atlas, faces, cap, tint, geometry)
          end)

        {px, py} = place(position, geometry)

        placed =
          for storey <- storeys..(storeys + height - 1)//1,
              do: {cube, {round(px + left), round(py + above - storey * geometry.block_h)}}

        {stamps ++ placed, storeys + height}
    end
  end

  defp facing_sides(atlas, art, at, geometry) do
    for {name, normal, from, to} <- @faces,
        {_nx, ny} = screen_normal(normal, geometry),
        ny > 0,
        do: {face_at(atlas, art, name, at), normal, from, to}
  end

  defp mover_items(atlas, movers, geometry, at) do
    for mover <- movers do
      {art, {x, y}, heading} = with_heading(mover)
      {pose, flip} = pose(heading, geometry)
      sprite = Atlas.pose(atlas, art, pose, at)

      stamp =
        stamp(atlas, {:upright, sprite.id, nil, flip}, geometry, fn ->
          upright(atlas, sprite, nil, flip)
        end)

      %{
        depth: depth_of({x, y}, geometry),
        stamps: [standing(stamp, place({x, y}, geometry), geometry)]
      }
    end
  end

  defp with_heading({art, position}), do: {art, position, nil}
  defp with_heading({art, position, heading}), do: {art, position, heading}

  defp pose(nil, _facing), do: {:front, false}

  defp pose(heading, geometry) do
    {hx, hy} = rotate({:math.cos(heading), :math.sin(heading)}, geometry)
    {if(hx + hy >= 0, do: :front, else: :back), hx - hy < 0}
  end

  defp standing(stamp, {foot_x, foot_y}, geometry),
    do:
      {stamp,
       {round(foot_x - stamp.width / 2), round(foot_y + geometry.half_h / 4 - stamp.height)}}

  defp label(canvas, {text, position, colour}, geometry),
    do: label(canvas, {text, position, colour, []}, geometry)

  defp label(canvas, {text, position, colour, opts}, geometry) do
    rendered =
      Raster.finalize(Linocut.Font.render(text, colour, scale: Keyword.get(opts, :scale, 1)))

    {px, py} = place(position, geometry)

    stamp =
      Canvas.stamp(%{
        width: rendered.width,
        height: rendered.height,
        rgba: Raster.to_rgba_binary(rendered)
      })

    Canvas.paint(canvas, stamp, {round(px - rendered.width / 2), round(py - rendered.height / 2)})
  end

  defp stamp(atlas, key, geometry, build) do
    Canvas.memo(
      Atlas.cache(atlas.name),
      {:iso, key, geometry.stamp_tile_h, geometry.shrink},
      fn ->
        build.() |> Canvas.shrink(geometry.shrink) |> Canvas.stamp()
      end
    )
  end

  defp turned(atlas, key, geometry, build) do
    Canvas.memo(
      Atlas.cache(atlas.name),
      {:iso, key, geometry.stamp_tile_h, geometry.shrink, geometry.facing, geometry.facings},
      fn ->
        %{offset: offset, image: image} = build.()
        %{stamp: Canvas.stamp(image), offset: offset}
      end
    )
  end

  defp face_at(atlas, art, face, at) do
    entry = Atlas.entry(atlas, art)

    case Map.get(entry.faces, face) || Map.get(entry.faces, :side) do
      nil -> Atlas.frame_at(atlas, art, at)
      sprite -> sprite
    end
  end

  defp tinted(_atlas, sprite, nil), do: Raster.to_rgba_binary(sprite.raster)

  defp tinted(atlas, sprite, tint) do
    fun = Map.fetch!(atlas.tints, tint)

    for <<r, g, b, a <- Raster.to_rgba_binary(sprite.raster)>>, into: <<>> do
      {tr, tg, tb, ta} = fun.({r, g, b, a})
      <<tr, tg, tb, ta>>
    end
  end

  defp upright(atlas, sprite, tint, flip) do
    image = %{width: sprite.width, height: sprite.height, rgba: tinted(atlas, sprite, tint)}
    if flip, do: Canvas.flip(image), else: image
  end
end
