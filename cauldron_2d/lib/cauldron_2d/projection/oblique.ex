defmodule Cauldron2D.Projection.Oblique do
  @moduledoc """
  Composes a view of the world on a square grid seen from above and in front: floors as
  squares, standing arts as a front face with their top above it, movers upright.

      Cauldron2D.Projection.Oblique.compose(:my_game,
        focus: {12.5, 8.5},
        cell: &MyGame.cell/1,
        size: {320, 200},
        movers: [{:hero, {12.5, 8.5}, heading}]
      )

  A tile of `t` pixels is drawn `t` wide and `t * squash` tall, and each storey raises
  what stands on it by `t * rise` pixels, so a wall shows `rise` of its side and the
  ground behind it is covered. Rows are painted back to front. There is no rotation:
  `+x` runs right and `+y` runs down and towards the viewer.

  ## Options

    * `:focus` — `{x, y}` in tiles, the world point at the picture's centre, required
    * `:cell` — `fn {x, y} -> cell end`, as `Cauldron2D.Surface` takes cells, required
    * `:size` — `{width, height}` of the picture in pixels, required
    * `:squash` — a row's height as a fraction of the tile, `0.25..1.0`. Default `0.5`
    * `:rise` — a storey's height as a fraction of the tile, `0.25..2.0`. Default `0.75`
    * `:movers` — `[{art, {x, y}}]` or `[{art, {x, y}, heading}]` in tiles, `heading` in
      radians with `0` along `+x`. A mover shows its `:front` pose when heading towards
      the viewer and `:back` when away, mirrored when heading left; with no heading it
      faces the viewer. Default `[]`
    * `:labels` — `[{text, {x, y}, colour}]` or with a fourth element of options as
      `Cauldron2D.Surface.compose/4` takes them, positioned by the tile. Default `[]`
    * `:volumes` — coloured regions of space, as `Cauldron2D.Projection.Volume`
      describes them, each tinting the rows behind it. Default `[]`
    * `:at` — the time in milliseconds an animated art's frame is chosen for. Default `0`

  `project/2`, `unproject/2` and `tile_at/2` map between picture pixels and world tiles
  for the same options; they answer for the ground, ignoring what stands on it.
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.{Canvas, Volume}
  alias FrenchCurve.Raster

  @face_shade 0.78

  @type option ::
          {:focus, {number(), number()}}
          | {:cell, ({integer(), integer()} -> Cauldron2D.Surface.cell())}
          | {:size, {pos_integer(), pos_integer()}}
          | {:squash, number()}
          | {:rise, number()}
          | {:movers, [tuple()]}
          | {:labels, [tuple()]}
          | {:volumes, [map()]}
          | {:at, integer()}

  @doc "The picture, as the module documentation describes."
  @spec compose(Atlas.name() | Atlas.t(), [option()]) :: Raster.t()
  def compose(atlas, opts) do
    atlas = Atlas.fetch(atlas)
    geometry = geometry(atlas, opts)
    {width, height} = geometry.size
    cell = Keyword.fetch!(opts, :cell)
    at = Keyword.get(opts, :at, 0)

    items =
      cell_items(geometry, cell, atlas, at) ++
        mover_items(Keyword.get(opts, :movers, []), atlas, geometry, at) ++
        volume_items(opts, geometry)

    canvas =
      items
      |> Enum.sort_by(& &1.row)
      |> Enum.reduce(Canvas.new(width, height, atlas.void), fn %{paint: paint}, acc ->
        paint.(acc)
      end)

    opts
    |> Keyword.get(:labels, [])
    |> Enum.reduce(canvas, &label(&2, &1, geometry))
    |> Canvas.to_raster()
  end

  @doc "Where world point `{x, y}` lands in the picture, in pixels from its top-left corner."
  @spec project(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) :: {float(), float()}
  def project(atlas, point, opts), do: place(point, geometry(Atlas.fetch(atlas), opts))

  @doc "The world point under picture pixel `{px, py}`, on the ground."
  @spec unproject(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) ::
          {float(), float()}
  def unproject(atlas, pixel, opts), do: ground_at(pixel, geometry(Atlas.fetch(atlas), opts))

  @doc "The tile under picture pixel `{px, py}`."
  @spec tile_at(Atlas.name() | Atlas.t(), {number(), number()}, [option()]) ::
          {integer(), integer()}
  def tile_at(atlas, point, opts) do
    {x, y} = unproject(atlas, point, opts)
    {floor(x), floor(y)}
  end

  defp geometry(atlas, opts) do
    tile = atlas.tile
    squash = opts |> Keyword.get(:squash, 0.5) |> min(1.0) |> max(0.25)
    rise = opts |> Keyword.get(:rise, 0.75) |> min(2.0) |> max(0.25)
    {width, height} = Keyword.fetch!(opts, :size)

    %{
      tile: tile,
      row_h: max(2, round(tile * squash)),
      lift: max(1, round(tile * rise)),
      focus: Keyword.fetch!(opts, :focus),
      size: {width, height},
      centre: {width / 2, height / 2}
    }
  end

  defp place({x, y}, geometry) do
    {fx, fy} = geometry.focus
    {cx, cy} = geometry.centre
    {cx + (x - fx) * geometry.tile, cy + (y - fy) * geometry.row_h}
  end

  defp cell_items(geometry, cell, atlas, at) do
    for {{_x, y} = position, tile} <- rows(geometry, cell) do
      %{row: y, paint: &column(&1, atlas, position, tile, geometry, at)}
    end
  end

  defp mover_items(movers, atlas, geometry, at) do
    for {_art, {_x, y}, _heading} = walker <- Enum.map(movers, &with_heading/1) do
      %{row: y, paint: &mover(&1, atlas, walker, geometry, at)}
    end
  end

  defp volume_items(opts, geometry) do
    for %{at: {_x, y}} = volume <- Volume.list(Keyword.get(opts, :volumes, [])) do
      %{row: y, paint: &volume(&1, volume, geometry)}
    end
  end

  defp volume(canvas, volume, geometry) do
    across = {geometry.tile, 0}
    down = {0, geometry.row_h}
    direction = Volume.eyeline(across, down, geometry.lift)
    plan = Volume.ground_plan(&ground_at(&1, geometry), direction)

    Volume.paint(canvas, volume, Volume.box(volume, &solid(&1, geometry)), plan)
  end

  defp solid({x, y, z}, geometry) do
    {sx, sy} = place({x, y}, geometry)
    {sx, sy - z * geometry.lift}
  end

  defp ground_at({px, py}, geometry) do
    {cx, cy} = geometry.centre
    {fx, fy} = geometry.focus
    {fx + (px - cx) / geometry.tile, fy + (py - cy) / geometry.row_h}
  end

  defp rows(geometry, cell) do
    {width, height} = geometry.size
    {fx, fy} = geometry.focus
    across = ceil(width / geometry.tile / 2) + 2
    down = ceil(height / geometry.row_h / 2) + ceil(4 * geometry.lift / geometry.row_h) + 2

    for y <- (floor(fy) - down)..(floor(fy) + down)//1,
        x <- (floor(fx) - across)..(floor(fx) + across)//1,
        tile = cell.({x, y}),
        tile != :void,
        do: {{x, y}, tile}
  end

  defp column(canvas, atlas, position, {base, overlays, tint}, geometry, at) do
    {sx, sy} = place(position, geometry)
    standing = for art <- [base | overlays], Atlas.entry(atlas, art).height > 0, do: art
    flat = for art <- overlays, Atlas.entry(atlas, art).height == 0, do: art

    canvas = ground(canvas, atlas, base, tint, {sx, sy}, geometry, at)

    {canvas, storeys} =
      Enum.reduce(standing, {canvas, 0}, &block(&2, atlas, &1, tint, {sx, sy}, geometry, at))

    Enum.reduce(flat, canvas, fn art, acc ->
      upright(acc, atlas, Atlas.frame_at(atlas, art, at), false, {sx, sy}, storeys, geometry)
    end)
  end

  defp ground(canvas, atlas, base, tint, {sx, sy}, geometry, at) do
    top = face_at(atlas, base, :top, at)

    stamp =
      stamp(atlas, {:ground, top.id, tint, geometry.row_h}, fn ->
        squashed(atlas, top, tint, geometry, 1.0)
      end)

    Canvas.paint(canvas, stamp, {round(sx), round(sy)})
  end

  defp block({canvas, storeys}, atlas, art, tint, {sx, sy}, geometry, at) do
    height = Atlas.entry(atlas, art).height
    side = face_at(atlas, art, :south, at)
    top = face_at(atlas, art, :top, at)

    face =
      stamp(atlas, {:face, side.id, tint, geometry.lift, height}, fn ->
        wall(atlas, side, tint, geometry, height)
      end)

    cap =
      stamp(atlas, {:cap, top.id, tint, geometry.row_h}, fn ->
        squashed(atlas, top, tint, geometry, 1.0)
      end)

    raised = storeys * geometry.lift
    face_top = round(sy + geometry.row_h - raised - height * geometry.lift)

    canvas =
      canvas
      |> Canvas.paint(face, {round(sx), face_top})
      |> Canvas.paint(cap, {round(sx), face_top - geometry.row_h})

    {canvas, storeys + height}
  end

  defp mover(canvas, atlas, mover, geometry, at) do
    {art, {x, y}, heading} = with_heading(mover)
    {pose, flip} = pose(heading)
    sprite = Atlas.pose(atlas, art, pose, at)
    {sx, sy} = place({x, y}, geometry)

    upright(
      canvas,
      atlas,
      sprite,
      flip,
      {sx - geometry.tile / 2, sy - geometry.row_h / 2},
      0,
      geometry
    )
  end

  defp upright(canvas, atlas, sprite, flip, {sx, sy}, storeys, geometry) do
    stamp =
      stamp(atlas, {:upright, sprite.id, flip}, fn ->
        image = %{
          width: sprite.width,
          height: sprite.height,
          rgba: Raster.to_rgba_binary(sprite.raster)
        }

        if flip, do: Canvas.flip(image), else: image
      end)

    left = round(sx + geometry.tile / 2 - stamp.width / 2)
    bottom = round(sy + geometry.row_h - storeys * geometry.lift)
    Canvas.paint(canvas, stamp, {left, bottom - stamp.height})
  end

  defp with_heading({art, position}), do: {art, position, nil}
  defp with_heading({art, position, heading}), do: {art, position, heading}

  defp pose(nil), do: {:front, false}

  defp pose(heading) do
    {hx, hy} = {:math.cos(heading), :math.sin(heading)}

    cond do
      hy > 0.5 -> {:front, false}
      hy < -0.5 -> {:back, false}
      true -> {:side, hx < 0}
    end
  end

  defp squashed(atlas, top, tint, geometry, factor) do
    tile = geometry.tile
    row_h = geometry.row_h
    texture = tinted(atlas, top, tint)

    rgba =
      for y <- 0..(row_h - 1)//1, x <- 0..(tile - 1)//1, into: <<>> do
        Canvas.shade(Canvas.texel(texture, tile, x / tile, y / row_h), factor, atlas.void, 0)
      end

    %{width: tile, height: row_h, rgba: rgba}
  end

  defp wall(atlas, side, tint, geometry, storeys) do
    tile = geometry.tile
    height = storeys * geometry.lift
    texture = tinted(atlas, side, tint)

    rgba =
      for y <- 0..(height - 1)//1, x <- 0..(tile - 1)//1, into: <<>> do
        v = rem(y, geometry.lift) / geometry.lift
        Canvas.shade(Canvas.texel(texture, tile, x / tile, v), @face_shade, atlas.void, 0)
      end

    %{width: tile, height: height, rgba: rgba}
  end

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

  defp stamp(atlas, key, build),
    do:
      Canvas.memo(Atlas.cache(atlas.name), {:oblique, key}, fn -> build.() |> Canvas.stamp() end)

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
end
