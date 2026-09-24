defmodule Cauldron2D.Surface do
  @moduledoc """
  Composites a grid of cells into one `FrenchCurve.Raster`.

  ## Cells

      :void                       nothing here
      {base, overlays, tint}      a tile, what is on it in paint order, and how it is shaded

  `overlays` is ordered bottom to top and may be empty. `tint` is `nil` or the name of a tint
  registered on the atlas.

  `base` must be an art of the atlas's tile size. An overlay may be any size: one the tile's
  size is blended into its cell; any other stands on its cell, its bottom edge on the cell's
  bottom edge and centred across it, drawn over every cell and tinted with its cell's tint.

  Overlays and movers are composited source-over: a half-transparent sprite on a
  half-transparent base leaves the result more opaque than either, not as opaque as the more
  opaque of the two. Over an opaque base — which most tiles are — this is the same arithmetic
  as a straight weighted mix.

  ## Movers

  `compose/3` also takes sprites placed at arbitrary pixel offsets rather than on the grid,
  as `[{art, {x, y}}]` where `{x, y}` is the sprite's top-left corner in the raster's own
  pixel coordinates. A mover is drawn at its art's own size, over the grid and its standing
  overlays, in list order, and clipped to the raster's edges. `blit/4` draws one onto an
  existing raster.

  A mover may also be `{art, {x, y}, tint}`, or `{art, {x, y}, tint, pose, flip}` to draw
  one of the art's poses — `:front`, `:back`, `:side` — mirrored when `flip` is true, so a
  view that knows which way a mover faces can show it.

  ## Labels

  `compose/4` also takes `:labels`, text drawn in `Linocut.Font` over everything else:
  `[{text, {x, y}, colour}]` or `[{text, {x, y}, colour, opts}]`, positioned by the
  text's top-left corner in the raster's pixel coordinates, with `opts` of `:scale`
  (default `1`) and `:background`, a colour filled behind the text (default none).

  ## Volumes

  `compose/4` also takes `:volumes`, coloured regions of space as
  `Cauldron2D.Projection.Volume` describes them, seen from directly above. A volume's
  `:at` is in tiles from the grid's top-left corner, and its shape is in tiles. Each
  tints the grid and everything drawn on it, by how much of it a viewer looking straight
  down has to see through.

  ## Caching

  Each distinct cell is blended once and the result kept in the atlas's ETS table, keyed by
  the sprite ids of its base and overlays together with the tint name. Two art names with
  byte-identical rasters share one entry.

  The cache outlives `Cauldron2D.Atlas.install/1` when the atlas installed is the same one.
  Installing a changed atlas — new art, a redefined tint, a different void colour — empties it,
  so a tint re-registered under a name it already had takes effect rather than serving tiles as
  they used to look.
  """

  alias Cauldron2D.Atlas
  alias Cauldron2D.Projection.Volume
  alias FrenchCurve.Raster

  @type cell :: :void | {Atlas.art(), [Atlas.art()], Atlas.tint() | nil}

  @doc """
  Compose `rows` — a list of equal-length rows of cells — into a raster.

  The raster is `columns * tile` pixels wide by `length(rows) * tile` tall, where `columns` is
  the length of the first row. Every row must be that same length.

  `movers` are `[{art, {x, y}}]` drawn over the grid in list order, positioned by their
  top-left corner in the raster's pixel coordinates rather than snapped to the grid.
  Coordinates may be fractional and are rounded; parts falling outside the raster are clipped.
  Default `[]`.

  An empty `rows` yields a `tile` by `tile` raster rather than a zero-sized one.

  ## Options

    * `:scale` — a positive integer dividing the tile size; the raster is composed at
      `1 / scale` of the atlas's resolution, every tile and sprite sampled once and kept in
      the atlas's cache table. Mover coordinates stay in full-resolution pixels. Default `1`
    * `:at` — the time in milliseconds an animated art's frame is chosen for. Default `0`,
      the first frame of everything
    * `:labels` — text drawn over the grid and the movers, as the module documentation
      describes. Default `[]`
    * `:volumes` — coloured regions tinting everything beneath them, as the module
      documentation describes. Default `[]`
  """
  @spec compose(
          Atlas.name() | Atlas.t(),
          [[cell()]],
          [{Atlas.art(), {number(), number()}}],
          keyword()
        ) ::
          Raster.t()
  def compose(atlas, rows, movers \\ [], opts \\ [])

  def compose(atlas, [], _movers, opts) do
    tile = div(Atlas.fetch(atlas).tile, Keyword.get(opts, :scale, 1))
    Raster.new(tile, tile)
  end

  def compose(atlas, rows, movers, opts) do
    atlas = Atlas.fetch(atlas)
    scale = Keyword.get(opts, :scale, 1)
    at = Keyword.get(opts, :at, 0)
    tile = div(atlas.tile, scale)
    columns = rows |> hd() |> length()
    {width, height} = {columns * tile, length(rows) * tile}

    {fitted, standing} = fit_to_grid(atlas, rows)
    grid = grid_rows(atlas, fitted, tile, scale, at)
    labels = Keyword.get(opts, :labels, [])
    volumes = Volume.list(Keyword.get(opts, :volumes, []))

    pixels =
      case {standing ++ movers, labels, volumes} do
        {[], [], []} ->
          grid

        {sprites, _labels, _volumes} ->
          paint(atlas, grid, sprites, labels, volumes, {width, height, tile}, scale, at)
      end

    Raster.from_rgba(width, height, IO.iodata_to_binary(pixels))
  end

  defp fit_to_grid(atlas, rows) do
    {fitted, standing} =
      rows
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {row, y}, acc ->
        {cells, standing} =
          row
          |> Enum.with_index()
          |> Enum.map_reduce([], fn {cell, x}, acc -> split_cell(atlas, cell, {x, y}, acc) end)

        {cells, acc ++ Enum.reverse(standing)}
      end)

    {fitted, standing}
  end

  defp split_cell(_atlas, :void, _position, acc), do: {:void, acc}

  defp split_cell(atlas, {base, overlays, tint}, {x, y}, acc) do
    tile = atlas.tile

    {fitting, standing} =
      Enum.split_with(overlays, fn art -> Atlas.entry(atlas, art).size == {tile, tile} end)

    placed =
      for art <- standing do
        {width, height} = Atlas.entry(atlas, art).size
        {art, {x * tile + (tile - width) / 2, (y + 1) * tile - height}, tint}
      end

    {{base, fitting, tint}, Enum.reverse(placed) ++ acc}
  end

  defp grid_rows(atlas, rows, tile, scale, at) do
    Enum.map(rows, fn row ->
      tiles = Enum.map(row, &tile_binary(atlas, &1, scale, at))
      for py <- 0..(tile - 1)//1, do: Enum.map(tiles, &binary_part(&1, py * tile * 4, tile * 4))
    end)
  end

  defp paint(atlas, grid, movers, labels, volumes, {width, height, tile}, scale, at) do
    lines =
      grid
      |> Enum.flat_map(fn tile_row -> Enum.map(tile_row, &IO.iodata_to_binary/1) end)
      |> Enum.with_index()
      |> Map.new(fn {line, index} -> {index, line} end)

    lines = Enum.reduce(movers, lines, &blit_sprite(atlas, &1, &2, width, height, scale, at))
    lines = Enum.reduce(labels, lines, &blit_label(&1, &2, width, height, scale))
    lines = Enum.reduce(volumes, lines, &blit_volume(&1, &2, {width, height}, tile))

    for y <- 0..(height - 1)//1, do: Map.fetch!(lines, y)
  end

  defp blit_volume(volume, lines, {width, height}, tile) do
    box = Volume.box(volume, fn {x, y, _z} -> {x * tile, y * tile} end)
    plan = Volume.ground_plan(fn {px, py} -> {px / tile, py / tile} end, {0.0, 0.0, 1.0})
    canvas = %{width: width, height: height, rows: lines}

    Volume.paint(canvas, volume, box, plan).rows
  end

  defp blit_sprite(atlas, {art, position}, lines, width, height, scale, at),
    do: blit_sprite(atlas, {art, position, nil, nil, false}, lines, width, height, scale, at)

  defp blit_sprite(atlas, {art, position, tint}, lines, width, height, scale, at),
    do: blit_sprite(atlas, {art, position, tint, nil, false}, lines, width, height, scale, at)

  defp blit_sprite(atlas, {art, {x, y}, tint, pose, flip}, lines, width, height, scale, at) do
    {binary, sprite_width, sprite_height} =
      sprite_binary(atlas, art, tint, {pose, flip}, scale, at)

    blit_binary(
      {binary, sprite_width, sprite_height},
      {round(x / scale), round(y / scale)},
      lines,
      width,
      height
    )
  end

  defp blit_label({text, position, colour}, lines, width, height, scale),
    do: blit_label({text, position, colour, []}, lines, width, height, scale)

  defp blit_label({text, {x, y}, colour, opts}, lines, width, height, scale) do
    raster = label_raster(text, colour, opts)

    blit_binary(
      {raster.rgba, raster.width, raster.height},
      {round(x / scale), round(y / scale)},
      lines,
      width,
      height
    )
  end

  defp label_raster(text, colour, opts) do
    rendered = Linocut.Font.render(text, colour, scale: Keyword.get(opts, :scale, 1))

    case Keyword.get(opts, :background) do
      nil ->
        Raster.finalize(rendered)

      background ->
        {r, g, b, a} = Linocut.Palette.color(background)

        backing =
          Raster.new(rendered.width, rendered.height, background: {r, g, b, a})
          |> Raster.finalize()

        Raster.from_rgba(
          rendered.width,
          rendered.height,
          over(backing.rgba, Raster.to_rgba_binary(rendered), [])
        )
    end
  end

  defp blit_binary({binary, cols, rows}, {left, top}, lines, width, height) do
    for sy <- 0..(rows - 1)//1, row = top + sy, row >= 0 and row < height, reduce: lines do
      acc ->
        Map.update!(
          acc,
          row,
          &blend_line(&1, binary_part(binary, sy * cols * 4, cols * 4), left, cols, width)
        )
    end
  end

  defp blend_line(line, sprite_row, left, tile, width) do
    clipped_left = max(0, -left)
    start = max(0, left)
    visible = min(tile - clipped_left, width - start)

    if visible <= 0 do
      line
    else
      source = binary_part(sprite_row, clipped_left * 4, visible * 4)
      beneath = binary_part(line, start * 4, visible * 4)
      merged = over(beneath, source, [])
      tail = start + visible

      IO.iodata_to_binary([
        binary_part(line, 0, start * 4),
        merged,
        binary_part(line, tail * 4, (width - tail) * 4)
      ])
    end
  end

  @doc """
  Draw the sprite `art` onto `raster` with its top-left corner at `{x, y}` in pixels.

  Coordinates may be fractional and are rounded; parts falling outside the raster are clipped.
  Returns a new raster; `raster` is unchanged.
  """
  @spec blit(Atlas.name() | Atlas.t(), Raster.t(), Atlas.art(), {number(), number()}) ::
          Raster.t()
  def blit(atlas, %Raster{} = raster, art, {x, y}) do
    atlas = Atlas.fetch(atlas)
    width = raster.width

    lines =
      for row <- 0..(raster.height - 1)//1,
          into: %{},
          do: {row, binary_part(raster.rgba, row * width * 4, width * 4)}

    painted = blit_sprite(atlas, {art, {x, y}}, lines, width, raster.height, 1, 0)

    Raster.from_rgba(
      width,
      raster.height,
      IO.iodata_to_binary(for row <- 0..(raster.height - 1)//1, do: Map.fetch!(painted, row))
    )
  end

  @doc "The raster `times` as wide and tall, every pixel repeated that many times each way; the raster itself at 1."
  @spec magnify(Raster.t(), pos_integer()) :: Raster.t()
  def magnify(%Raster{} = raster, 1), do: raster

  def magnify(%Raster{width: width, height: height} = raster, times)
      when is_integer(times) and times > 1 do
    rows = for <<row::binary-size(width * 4) <- Raster.to_rgba_binary(raster)>>, do: row

    wide =
      for row <- rows,
          do: for(<<pixel::binary-4 <- row>>, into: <<>>, do: :binary.copy(pixel, times))

    tall = for row <- wide, into: <<>>, do: :binary.copy(row, times)
    Raster.from_rgba(width * times, height * times, tall)
  end

  @doc """
  The flat RGBA binary for one cell, `tile * tile * 4` bytes long, with animated arts at
  the frame showing at `at` milliseconds.

  Blends the cell on first sight and keeps the result in the atlas's cache table, which
  `Cauldron2D.Atlas.install/1` must have created.
  """
  @spec tile_binary(Atlas.name() | Atlas.t(), cell(), pos_integer(), integer()) :: binary()
  def tile_binary(atlas, cell, scale \\ 1, at \\ 0) do
    atlas = Atlas.fetch(atlas)

    cached(
      atlas,
      scaled_key(cache_key(atlas, cell, at), scale),
      fn -> blend(atlas, cell, at) end,
      {atlas.tile, atlas.tile},
      scale
    )
  end

  defp sprite_binary(atlas, art, tint, {pose, flip}, scale, at) do
    sprite = posed(atlas, art, pose, at)
    size = {sprite.width, sprite.height}

    binary =
      cached(
        atlas,
        scaled_key({:sprite, sprite.id, tint, flip}, scale),
        fn -> sprite.raster.rgba |> shade(atlas, tint) |> mirrored(flip, sprite.width) end,
        size,
        scale
      )

    {binary, div(sprite.width, scale), div(sprite.height, scale)}
  end

  defp posed(atlas, art, nil, at), do: Atlas.frame_at(atlas, art, at)
  defp posed(atlas, art, pose, at), do: Atlas.pose(atlas, art, pose, at)

  defp mirrored(rgba, false, _width), do: rgba

  defp mirrored(rgba, true, width) do
    stride = width * 4

    for <<row::binary-size(^stride) <- rgba>>, into: <<>> do
      row
      |> then(&for(<<pixel::binary-size(4) <- &1>>, do: pixel))
      |> Enum.reverse()
      |> IO.iodata_to_binary()
    end
  end

  defp scaled_key(key, 1), do: key
  defp scaled_key(key, scale), do: {key, {:scale, scale}}

  defp cached(atlas, key, full, size, scale) do
    table = Atlas.cache(atlas.name)

    case :ets.lookup(table, key) do
      [{^key, binary}] ->
        binary

      [] ->
        binary = sample(full.(), size, scale)
        :ets.insert(table, {key, binary})
        binary
    end
  end

  defp sample(binary, _size, 1), do: binary

  defp sample(binary, {width, height}, scale) do
    {small_w, small_h} = {div(width, scale), div(height, scale)}

    for py <- 0..(small_h - 1)//1, px <- 0..(small_w - 1)//1, into: <<>> do
      binary_part(binary, (py * scale * width + px * scale) * 4, 4)
    end
  end

  defp cache_key(_atlas, :void, _at), do: :void

  defp cache_key(atlas, {base, overlays, tint}, at) do
    {Atlas.frame_at(atlas, base, at).id, Enum.map(overlays, &Atlas.frame_at(atlas, &1, at).id),
     tint}
  end

  defp blend(atlas, :void, _at) do
    {r, g, b} = atlas.void
    :binary.copy(<<r, g, b, 255>>, atlas.tile * atlas.tile)
  end

  defp blend(atlas, {base, overlays, tint}, at) do
    overlays
    |> Enum.reduce(tile_rgba(atlas, base, at), fn art, beneath ->
      over(beneath, Atlas.frame_at(atlas, art, at).raster.rgba, [])
    end)
    |> shade(atlas, tint)
  end

  defp tile_rgba(atlas, base, at) do
    case Atlas.frame_at(atlas, base, at) do
      %{width: width, height: height} = sprite
      when width == atlas.tile and height == atlas.tile ->
        sprite.raster.rgba

      %{width: width, height: height} ->
        raise ArgumentError,
              "#{inspect(base)} is #{width}x#{height} but a tile's base must be " <>
                "#{atlas.tile}x#{atlas.tile}; only overlays and movers may be another size"
    end
  end

  defp over(<<>>, <<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp over(<<br, bg, bb, ba, base::binary>>, <<_tr, _tg, _tb, 0, top::binary>>, acc) do
    over(base, top, [<<br, bg, bb, ba>> | acc])
  end

  defp over(<<_br, _bg, _bb, _ba, base::binary>>, <<tr, tg, tb, 255, top::binary>>, acc) do
    over(base, top, [<<tr, tg, tb, 255>> | acc])
  end

  defp over(<<br, bg, bb, ba, base::binary>>, <<tr, tg, tb, ta, top::binary>>, acc) do
    top_alpha = ta / 255
    base_alpha = ba / 255 * (1 - top_alpha)
    alpha = top_alpha + base_alpha

    pixel =
      <<mix(tr, br, top_alpha, base_alpha, alpha), mix(tg, bg, top_alpha, base_alpha, alpha),
        mix(tb, bb, top_alpha, base_alpha, alpha), round(alpha * 255)>>

    over(base, top, [pixel | acc])
  end

  defp mix(top, bottom, top_alpha, base_alpha, alpha) do
    round((top * top_alpha + bottom * base_alpha) / alpha)
  end

  defp shade(binary, _atlas, nil), do: binary

  defp shade(binary, atlas, tint) do
    fun = Map.fetch!(atlas.tints, tint)

    for <<r, g, b, a <- binary>>, into: <<>> do
      {tr, tg, tb, ta} = fun.({r, g, b, a})
      <<tr, tg, tb, ta>>
    end
  end

  @doc """
  Apply the tint named `tint` to a plain RGB colour, for renderers that draw characters.

  The colour is passed to the tint function at full alpha and the alpha of the result is
  dropped. A `nil` tint returns the colour unchanged.
  """
  @spec shade_color(Atlas.name() | Atlas.t(), Atlas.rgb(), Atlas.tint() | nil) :: Atlas.rgb()
  def shade_color(_atlas, rgb, nil), do: rgb

  def shade_color(atlas, {r, g, b}, tint) do
    fun = atlas |> Atlas.fetch() |> Map.fetch!(:tints) |> Map.fetch!(tint)
    {tr, tg, tb, _a} = fun.({r, g, b, 255})
    {tr, tg, tb}
  end
end
