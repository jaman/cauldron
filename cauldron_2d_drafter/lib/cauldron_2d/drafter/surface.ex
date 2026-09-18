defmodule Cauldron2D.Drafter.Surface do
  @moduledoc """
  A drafter widget that draws a `Cauldron2D` surface.

      {:cauldron_surface,
       [
         id: :map,
         atlas: :my_game,
         focus: {x, y},
         cell: &MyGame.cell/1,
         movers: [{:ball, {7.42, 3.15}}],
         flex: 1
       ]}

  Register it before use, after loading it:

      Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
      Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

  Where `Cauldron2D.Renderer` finds a pixel protocol, `image/3` hands drafter one composited
  image and `render/2` fills the pane with blank cells beneath it. Otherwise `image/3` returns
  `nil` and `render/2` draws two-cell glyphs. Both read the same camera view, sized from the
  pane by `Cauldron2D.Camera.columns_for/1` and `Cauldron2D.Camera.rows_for/1`.

  Until both `:focus` and `:cell` are set, `render/2` fills the pane with black and `image/3`
  returns `nil`.

  ## Options

    * `:atlas` — the name an atlas was installed under with `Cauldron2D.Atlas.install/1`
    * `:focus`, `:cell` — passed to `Cauldron2D.Camera.view/1`
    * `:movers` — `[{art, {x, y}}]` in world tile coordinates, which may be fractional.
      Default `[]`. In pixel mode a mover is drawn at its exact pixel position; in text mode
      it replaces the glyph of the nearest whole cell
    * `:labels` — `[{text, {x, y}, colour}]` or `[{text, {x, y}, colour, opts}]` in world
      tile coordinates, as `Cauldron2D.Surface.compose/4` takes them: names, numbers,
      notes drawn over everything. Default `[]`. In pixel mode a label is drawn in
      `Linocut.Font` at its exact pixel position, with placements as a stored image of its
      own; in text mode its characters overlay the glyphs from the nearest cell
    * `:zoom` — how many times its native size a tile is drawn: `2` twice as large,
      `0.5` half, so a pane shows half or twice the tiles. Default `1`. Levels a
      surface draws exactly are `zoom_levels/2`'s; another is drawn at the nearest of
      them. In the pixel modes a tile is drawn at the whole multiple of its pixels
      nearest to `zoom` rows of cells, or shrunk by a divisor of its size below half
      a tile, so the terminal scales nothing (`Cauldron2D.Drafter.Surface.Scale`);
      where the session does not know the cell size the frame is fitted to the
      pane's cells by the terminal instead. In text mode a tile zoomed in covers that
      many more cells; zoomed out, every that-manyeth tile is drawn
    * `:mode` — a `Cauldron2D.Renderer` mode to force instead of detecting one, or
      `:braille`: the frame composed at four dots per tile side, pixels at or above a
      luminance of 64 lit, drawn as braille text in the colour of each cell's lit pixels.
      Default `nil`
    * `:compress` — zlib the kitty transmit. Default `true`
    * `:placements` — `:auto` (default), `true` or `false`. Whether movers are drawn as
      stored sprites placed at pixel offsets rather than composited into the frame; see
      below
    * `:on_geometry` — an event name sent to the application whenever the pane's rect changes,
      see `on_rect_change/2`. Default `nil`
    * `:image_throttle`, `:image_priority` — how often a new frame is composed and at
      what scheduler priority, as drafter's widget server takes them. Defaults: every
      second application frame, `:low`. A game animating at the application's frame rate
      passes `image_throttle: {1, :tick}, image_priority: :normal`

  ## Scrolling

  In both pixel renderings the focus sits at the exact centre of the pane: the grid is
  composed one tile wider and taller than the pane and shown through a window shifted by
  the fraction of a tile the focus is past a tile boundary, and movers are placed
  relative to that same fractional origin. Text mode scrolls by whole tiles.

  ## Animation

  An art with frames (`Cauldron2D.Atlas.put/4` with a list) is drawn at the frame showing
  on the session's monotonic clock, in every rendering but glyphs. The grid image of the
  placement rendering is sent again when a frame changes; a mover with frames is placed
  by the frame's own stored image.

  ## Placements

  On a kitty terminal whose cell size the session knows
  (`Drafter.Session.Context.cell_size/0`, asked for with `use Drafter.App, cell_size: true`),
  the grid is one stored image sent again only when its tiles or the atlas change, and
  each mover is a placement of a sprite stored by `Cauldron2D.Drafter.Sprites.transmit/2`
  — a few dozen bytes per mover per frame, no pixels. The surface stores the sprites
  itself, at the size they are drawn, once per size and atlas. Zoomed out below half a
  tile, and elsewhere, the movers are composited into one image per frame.

  The protocol is the one the session's terminal answered the startup probe with, or
  `Cauldron2D.Renderer`'s detection when there was no probe.
  """

  use Drafter.Widget, handles: []

  require Logger

  alias Cauldron2D.{Atlas, Camera, Renderer, Surface}
  alias Cauldron2D.Drafter.Sprites
  alias Cauldron2D.Drafter.Surface.Scale
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Session.Context
  alias Drafter.Terminal.ANSI
  alias FrenchCurve.Backend.{Braille, Kitty}
  alias FrenchCurve.Raster

  defstruct [
    :atlas,
    :focus,
    :cell,
    :widget_id,
    :on_geometry,
    :rect,
    movers: [],
    labels: [],
    mode: nil,
    zoom: 1,
    compress: true,
    placements: :auto
  ]

  @braille_dots 4
  @braille_luminance 64
  @zoom_in [4, 2]
  @zoom_out [2, 4, 8, 16]

  @doc """
  The zoom levels a surface draws exactly, largest first: in `:text` mode and the pixel
  modes (`:kitty`, `:iterm2`, `:sixel`, or `nil` for whichever is detected) 4 down to a
  sixteenth, kept to the divisors of the atlas's tile size zoomed out; in `:braille` mode
  those where a tile is a whole number of dots, from the tile's size in dots down to one.
  """
  @spec zoom_levels(Atlas.name(), atom() | nil) :: [number()]
  def zoom_levels(atlas, mode) do
    tile = Atlas.fetch(atlas).tile

    case mode do
      :braille ->
        for divisor <- divisors(tile), do: tile / (@braille_dots * divisor)

      :text ->
        @zoom_in ++ [1 | Enum.map(@zoom_out, &(1 / &1))]

      _pixel ->
        @zoom_in ++ [1 | for(divisor <- @zoom_out, rem(tile, divisor) == 0, do: 1 / divisor)]
    end
    |> Enum.map(&whole/1)
  end

  defp divisors(tile), do: for(divisor <- 1..tile, rem(tile, divisor) == 0, do: divisor)

  defp whole(number) when is_float(number) and number == trunc(number), do: trunc(number)
  defp whole(number), do: number

  @type t :: %__MODULE__{}

  @doc "The tag this widget answers to in a component tree: `:cauldron_surface`."
  @spec component_tag() :: atom()
  def component_tag, do: :cauldron_surface

  @doc false
  @spec from_component_opts(term(), keyword()) :: map()
  def from_component_opts(_args, opts) do
    opts
    |> Keyword.take([
      :atlas,
      :focus,
      :cell,
      :movers,
      :labels,
      :mode,
      :zoom,
      :compress,
      :placements,
      :on_geometry
    ])
    |> Map.new()
    |> Map.put(:id, Keyword.get(opts, :__widget_id__))
  end

  @doc """
  Build the widget's state from its props.

  Props may be a map or a keyword list. Every key falls back to its documented default when
  absent, so `compress: false` means false rather than the default.
  """
  @impl true
  @spec mount(map() | keyword()) :: t()
  def mount(props) do
    props = Map.new(props)

    %__MODULE__{
      atlas: Map.get(props, :atlas),
      focus: Map.get(props, :focus),
      cell: Map.get(props, :cell),
      movers: Map.get(props, :movers) || [],
      labels: Map.get(props, :labels) || [],
      mode: Map.get(props, :mode),
      compress: Map.get(props, :compress, true),
      placements: Map.get(props, :placements, :auto),
      on_geometry: Map.get(props, :on_geometry),
      widget_id: Map.get(props, :id)
    }
  end

  @doc """
  Fold re-rendered props into the widget state.

  Every option the widget takes can be changed by a re-render, not only the camera ones. A key
  present in `props` is used even when its value is `nil` or `false`, so a mode that was forced
  can be unforced and `compress` can be turned off. A key absent from `props` leaves that part
  of the state as it was.
  """
  @impl true
  @spec update(map() | keyword(), t()) :: t()
  def update(props, %__MODULE__{} = state) do
    props = Map.new(props)

    %{
      state
      | focus: fold(props, :focus, state.focus),
        cell: fold(props, :cell, state.cell),
        movers: fold(props, :movers, state.movers) || [],
        labels: fold(props, :labels, state.labels) || [],
        atlas: fold(props, :atlas, state.atlas),
        mode: fold(props, :mode, state.mode),
        zoom: fold(props, :zoom, state.zoom) || 1,
        compress: fold(props, :compress, state.compress),
        placements: fold(props, :placements, state.placements),
        on_geometry: fold(props, :on_geometry, state.on_geometry)
    }
  end

  defp fold(props, key, current) do
    case Map.fetch(props, key) do
      {:ok, value} -> value
      :error -> current
    end
  end

  @doc """
  Record the pane's rect, and report it when it differs from the one already held.

  With `:on_geometry` set and a drafter application running, the application is sent
  `%{rect: rect, size: {columns, rows}}`, where `size` is the viewport in tiles. Those two,
  with `Cauldron2D.Camera.origin/3` and `Cauldron2D.Camera.tile_at/2`, are what maps a screen
  position back to a world tile.

  Returns the state carrying the new rect.
  """
  @spec on_rect_change(map(), t()) :: t()
  def on_rect_change(rect, %__MODULE__{} = state) do
    if state.on_geometry && rect != state.rect, do: announce(state, rect)

    %{state | rect: rect}
  end

  defp announce(%__MODULE__{widget_id: id, on_geometry: event}, rect) do
    if Drafter.AppRegistry.whereis() do
      geometry = %{
        rect: rect,
        size: {Camera.columns_for(rect.width), Camera.rows_for(rect.height)}
      }

      Drafter.AppRegistry.send_to_loop({:widget_action, id, {:app_callback, event, geometry}})
    end

    :ok
  end

  @impl true
  def render(%__MODULE__{focus: nil}, rect), do: blank(rect, {0, 0, 0})
  def render(%__MODULE__{cell: nil}, rect), do: blank(rect, {0, 0, 0})

  def render(%__MODULE__{mode: :braille} = state, rect), do: braille(state, rect)

  def render(%__MODULE__{} = state, rect) do
    case protocol(state) do
      nil -> glyphs(state, rect)
      _pixel -> blank(rect, Atlas.fetch(state.atlas).void)
    end
  end

  @doc """
  The pixel protocol this surface draws with, or `nil` for glyphs.

  A forced `:mode` wins; then the protocol the session's terminal answered the probe
  with; then, when the terminal was not probed or named no protocol,
  `Cauldron2D.Renderer.protocol/1`.
  """
  @spec protocol(t()) :: :kitty | :iterm2 | :sixel | nil
  def protocol(%__MODULE__{mode: :braille}), do: nil

  def protocol(%__MODULE__{mode: mode}) when mode in [:text, :kitty, :iterm2, :sixel],
    do: Renderer.protocol(mode)

  def protocol(%__MODULE__{mode: mode}) do
    case Context.terminal_protocol() do
      {:ok, protocol} when protocol != nil -> protocol
      _unknown -> Renderer.protocol(mode)
    end
  end

  defp blank(rect, background) do
    width = max(rect.width, 1)
    strip = Strip.new([Segment.new(String.duplicate(" ", width), %{bg: background})])
    List.duplicate(strip, max(rect.height, 1))
  end

  defp glyphs(%__MODULE__{} = state, rect) do
    atlas = Atlas.fetch(state.atlas)
    background = atlas.void
    zoom = nearest(state.zoom, zoom_levels(state.atlas, :text))
    columns = Camera.columns_for(rect.width)
    rows = Camera.rows_for(rect.height)
    camera = glyph_camera(state, {columns, rows}, zoom)

    atlas
    |> Camera.glyphs(camera)
    |> magnify(zoom, {columns, rows})
    |> overlay_movers(atlas, camera, zoom, state.movers)
    |> overlay_labels(camera, zoom, state.labels)
    |> Enum.map(fn row ->
      row
      |> Enum.map(fn {glyph, color} -> Segment.new(glyph, %{fg: color, bg: background}) end)
      |> Strip.new()
      |> Strip.fit_to_width(max(rect.width, 1))
    end)
  end

  defp glyph_camera(state, size, zoom) when zoom >= 1 do
    Camera.view(
      focus: state.focus,
      size: Camera.zoomed(size, zoom),
      cell: state.cell
    )
  end

  defp glyph_camera(state, {columns, rows}, zoom) do
    step = round(1 / zoom)
    {ox, oy} = origin = Camera.origin(state.focus, {columns * step, rows * step})

    cells =
      for row <- 0..(rows - 1),
          do:
            for(
              column <- 0..(columns - 1),
              do: state.cell.({ox + column * step, oy + row * step})
            )

    %Camera{origin: origin, columns: columns, rows: rows, cells: cells}
  end

  defp magnify(rows, zoom, _size) when zoom <= 1, do: rows

  defp magnify(rows, zoom, {columns, count}) do
    times = round(zoom)

    rows
    |> Enum.flat_map(fn row ->
      row
      |> Enum.flat_map(&List.duplicate(&1, times))
      |> Enum.take(columns)
      |> List.duplicate(times)
    end)
    |> Enum.take(count)
  end

  defp nearest(zoom, levels), do: Enum.min_by(levels, &abs(:math.log(&1 / zoom)))

  defp braille(%__MODULE__{} = state, rect) do
    atlas = Atlas.fetch(state.atlas)
    background = atlas.void
    columns = Camera.columns_for(rect.width)
    cells = max(1, rect.height)
    zoom = nearest(state.zoom, zoom_levels(state.atlas, :braille))
    camera = view(state, rect, true, zoom)
    scale = round(atlas.tile / (@braille_dots * zoom))
    {sx, sy} = scroll_pixels(camera, atlas.tile)

    atlas
    |> Surface.compose(camera.cells, pixel_movers(state, camera),
      scale: scale,
      at: now(),
      labels: pixel_labels(state, camera)
    )
    |> Raster.crop(
      {div(sx, scale), div(sy, scale)},
      {columns * @braille_dots, cells * @braille_dots}
    )
    |> lit_above(@braille_luminance)
    |> Braille.render()
    |> Enum.map(fn row ->
      row
      |> Enum.map(fn {char, color} ->
        Segment.new(char, %{fg: color || background, bg: background})
      end)
      |> Strip.new()
      |> Strip.fit_to_width(max(rect.width, 1))
    end)
  end

  defp lit_above(%Raster{} = raster, luminance) do
    keyed =
      for <<r, g, b, _a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        if r + g + b >= luminance * 3, do: <<r, g, b, 255>>, else: <<r, g, b, 0>>
      end

    Raster.from_rgba(raster.width, raster.height, keyed)
  end

  defp overlay_movers(rows, _atlas, _camera, _zoom, []), do: rows

  defp overlay_movers(rows, atlas, camera, zoom, movers) do
    {ox, oy} = camera.origin
    count = length(rows)

    Enum.reduce(movers, rows, fn {art, {x, y}}, acc ->
      column = floor((x - ox) * zoom)
      row = floor((y - oy) * zoom)
      entry = Atlas.entry(atlas, art)

      if row >= 0 and row < count and column >= 0 and column < length(Enum.at(acc, row)) do
        List.update_at(acc, row, &List.replace_at(&1, column, {entry.glyph, entry.color}))
      else
        acc
      end
    end)
  end

  defp overlay_labels(rows, _camera, _zoom, []), do: rows

  defp overlay_labels(rows, camera, zoom, labels) do
    {ox, oy} = camera.origin
    count = length(rows)

    Enum.reduce(labels, rows, fn label, acc ->
      {text, {x, y}, colour} = label_parts(label)

      overlay_label(acc, floor((y - oy) * zoom), count, fn cells ->
        write_chars(
          split_chars(cells),
          text,
          round((x - ox) * zoom * 2),
          colour,
          length(cells) * 2
        )
      end)
    end)
  end

  defp overlay_label(rows, row, count, write) when row >= 0 and row < count,
    do: List.update_at(rows, row, write)

  defp overlay_label(rows, _row, _count, _write), do: rows

  defp label_parts({text, position, colour}), do: {text, position, colour}
  defp label_parts({text, position, colour, _opts}), do: {text, position, colour}

  defp split_chars(cells) do
    Enum.flat_map(cells, fn {glyph, colour} ->
      for char <- String.graphemes(glyph), do: {char, colour}
    end)
  end

  defp write_chars(chars, text, start, colour, across) do
    text
    |> String.graphemes()
    |> Enum.with_index(start)
    |> Enum.reduce(chars, fn {char, column}, acc ->
      if column >= 0 and column < across,
        do: List.replace_at(acc, column, {char, colour}),
        else: acc
    end)
  end

  defp view(%__MODULE__{} = state, rect, scroll?, zoom) do
    Camera.view(
      focus: state.focus,
      size: Camera.zoomed({Camera.columns_for(rect.width), Camera.rows_for(rect.height)}, zoom),
      cell: state.cell,
      scroll: scroll?
    )
  end

  @doc """
  Produce the frame as terminal-graphics bytes, or `nil` when there is nothing to draw.

  Returns `nil` when `Cauldron2D.Renderer` finds no pixel protocol, when `:focus` or `:cell`
  is unset, or when composing the frame raises.

  A frame that raises is logged with its stacktrace before `nil` is returned, so a missing
  atlas or a bad mover shows up as an error rather than as a pane that is silently blank.
  Frames are drawn many times a second, so the same message is logged once per widget process
  rather than on every frame.

  Otherwise returns `{paint, clear, region}`:

    * `paint` — the bytes that draw this frame, which already begin with `clear`
    * `clear` — the bytes that remove this frame, empty for protocols that leave no stored
      image behind
    * `region` — `%{dx: 0, dy: 0, cols: cols, rows: rows, place: place}` covering the pane.
      `place` re-asserts an already-transmitted image's placement, and is `nil` for protocols
      whose bytes are the pixels themselves

  `id` identifies the image to the terminal across frames, so successive calls for the same
  widget must pass the same `id`.

  `FrenchCurve.frame/3` builds the bytes, which matters because not every terminal detected as
  `:kitty` keeps images under an id — iTerm does not, and a surface animated as though it did
  would never move.
  """
  @spec image(t(), map(), term()) :: {iodata(), iodata(), map()} | nil
  def image(%__MODULE__{focus: nil}, _rect, _id), do: nil
  def image(%__MODULE__{cell: nil}, _rect, _id), do: nil

  def image(%__MODULE__{} = state, rect, id) do
    case protocol(state) do
      nil -> nil
      protocol -> encode(state, rect, id, protocol)
    end
  rescue
    error ->
      report(state, error, __STACKTRACE__)
      nil
  end

  defp report(%__MODULE__{widget_id: id}, error, stacktrace) do
    message = Exception.message(error)
    seen = Process.get(__MODULE__, MapSet.new())

    unless MapSet.member?(seen, message) do
      Process.put(__MODULE__, MapSet.put(seen, message))

      Logger.error("""
      #{inspect(__MODULE__)} #{inspect(id)} could not compose a frame, so its pane is blank: \
      #{message}
      #{Exception.format_stacktrace(stacktrace)}\
      """)
    end

    :ok
  end

  defp encode(state, rect, id, protocol) do
    zoom = nearest(state.zoom, zoom_levels(state.atlas, protocol))

    case Context.cell_size() do
      nil -> fitted(state, rect, id, protocol, zoom)
      cell -> exact(state, rect, id, protocol, Scale.new(cell, tile(state), zoom))
    end
  end

  defp fitted(state, rect, id, protocol, zoom) do
    columns = Camera.columns_for(rect.width)
    cells = max(1, rect.height)
    raster = composed(state, rect, zoom, protocol, columns, cells)

    {paint, clear, place} =
      serialize(raster, protocol, {columns * 2, cells}, id, state.compress)

    {paint, clear, %{dx: 0, dy: 0, cols: columns * 2, rows: cells, place: place}}
  end

  defp composed(state, rect, zoom, protocol, columns, cells) when zoom >= 1 do
    tile = tile(state)
    camera = view(state, rect, true, zoom)

    raster =
      state.atlas
      |> Surface.compose(camera.cells, pixel_movers(state, camera),
        at: now(),
        labels: pixel_labels(state, camera)
      )
      |> Raster.crop(
        scroll_pixels(camera, tile),
        {round(columns * tile / zoom), round(cells * tile / zoom)}
      )

    if protocol == :sixel and zoom > 1, do: Surface.magnify(raster, round(zoom)), else: raster
  end

  defp composed(state, rect, zoom, _protocol, columns, cells) do
    tile = tile(state)
    scale = round(1 / zoom)
    camera = view(state, rect, true, zoom)
    {sx, sy} = scroll_pixels(camera, tile)

    state.atlas
    |> Surface.compose(camera.cells, pixel_movers(state, camera),
      scale: scale,
      at: now(),
      labels: pixel_labels(state, camera)
    )
    |> Raster.crop({div(sx, scale), div(sy, scale)}, {columns * tile, cells * tile})
  end

  defp exact(state, rect, id, protocol, %Scale{factor: {:magnify, _}} = scale) do
    if placements?(state, protocol),
      do: placed(state, rect, id, scale),
      else: composited(state, rect, id, protocol, scale)
  end

  defp exact(state, rect, id, protocol, scale), do: composited(state, rect, id, protocol, scale)

  defp composited(state, rect, id, protocol, scale) do
    raster = exact_raster(state, rect, scale)
    fit = if protocol == :iterm2, do: {rect.width, rect.height}
    {paint, clear, place} = serialize(raster, protocol, fit, id, state.compress)
    {paint, clear, %{dx: 0, dy: 0, cols: rect.width, rows: rect.height, place: place}}
  end

  defp exact_raster(state, rect, %Scale{factor: {:magnify, times}} = scale) do
    camera = exact_view(state, rect, scale)
    {sx, sy} = Scale.scroll(scale, camera.scroll)
    {width, height} = Scale.pane(scale, rect)

    state.atlas
    |> Surface.compose(camera.cells, pixel_movers(state, camera),
      at: now(),
      labels: pixel_labels(state, camera)
    )
    |> Raster.crop(
      {div(sx, times), div(sy, times)},
      {ceil(width / times) + 1, ceil(height / times) + 1}
    )
    |> Surface.magnify(times)
    |> Raster.crop({rem(sx, times), rem(sy, times)}, {width, height})
  end

  defp exact_raster(state, rect, %Scale{factor: {:reduce, divisor}} = scale) do
    camera = exact_view(state, rect, scale)

    state.atlas
    |> Surface.compose(camera.cells, pixel_movers(state, camera),
      scale: divisor,
      at: now(),
      labels: pixel_labels(state, camera)
    )
    |> Raster.crop(Scale.scroll(scale, camera.scroll), Scale.pane(scale, rect))
  end

  defp exact_view(state, rect, scale) do
    Camera.view(
      focus: state.focus,
      size: Scale.tiles(scale, rect),
      cell: state.cell,
      scroll: true
    )
  end

  defp tile(state), do: Atlas.fetch(state.atlas).tile

  defp placements?(%__MODULE__{placements: false}, _protocol), do: false
  defp placements?(%__MODULE__{placements: true}, :kitty), do: Context.cell_size() != nil

  defp placements?(%__MODULE__{placements: :auto}, :kitty) do
    Context.cell_size() != nil and session_placements?()
  end

  defp placements?(_state, _protocol), do: false

  defp session_placements? do
    case Context.terminal_protocol() do
      {:ok, :kitty} -> true
      {:ok, protocol} when protocol != nil -> false
      _unknown -> FrenchCurve.Capability.placements?()
    end
  end

  @sprite_layer 1

  defp scroll_pixels(%Camera{scroll: {sx, sy}}, tile), do: {round(sx * tile), round(sy * tile)}
  defp exact_origin(%Camera{origin: {ox, oy}, scroll: {sx, sy}}), do: {ox + sx, oy + sy}

  defp now, do: System.monotonic_time(:millisecond)

  defp placed(state, rect, id, %Scale{factor: {:magnify, times}} = scale) do
    atlas = Atlas.fetch(state.atlas)
    at = now()
    camera = exact_view(state, rect, scale)
    grid = atlas |> Surface.compose(camera.cells, [], at: at) |> Surface.magnify(times)
    image = FrenchCurve.image_id(id)
    {sx, sy} = Scale.scroll(scale, camera.scroll)
    {width, height} = Scale.pane(scale, rect)

    place = Kitty.place(image, placement: 1, source: {sx, sy, width, height})
    clear = Kitty.delete(id: image, placement: 1)
    paint = [clear, Kitty.transmit(grid, image, compress: state.compress), place]

    background =
      background_bytes(
        atlas,
        id,
        {camera.cells, animation_frames(atlas, at), times},
        paint,
        place
      )

    layer = [
      Kitty.delete(z: @sprite_layer)
      | sprite_placements(state, atlas, camera, rect, scale, at) ++
          label_placements(state, atlas, camera, rect, scale)
    ]

    {[sprites_stored(state, atlas, times), background, layer],
     [clear, Kitty.delete(z: @sprite_layer)],
     %{
       dx: 0,
       dy: 0,
       cols: rect.width,
       rows: rect.height,
       place: IO.iodata_to_binary([place, layer])
     }}
  end

  defp sprites_stored(state, atlas, times) do
    key = {__MODULE__, :sprites_sent}

    if Process.get(key) == {atlas, times} do
      []
    else
      Process.put(key, {atlas, times})
      Sprites.transmit(atlas, scale: times, compress: state.compress)
    end
  end

  defp background_bytes(atlas, id, cells, paint, place) do
    table = Atlas.cache(atlas.name)
    key = {:background, id}
    digest = :erlang.phash2(cells)

    case :ets.lookup(table, key) do
      [{^key, ^digest, ^atlas}] when place != nil ->
        place

      _changed ->
        :ets.insert(table, {key, digest, atlas})
        paint
    end
  end

  defp animation_frames(atlas, at) do
    for art <- Atlas.arts(atlas),
        Atlas.animated?(atlas, art),
        do: {art, Atlas.frame_index(atlas, art, at)}
  end

  defp sprite_placements(%__MODULE__{movers: []}, _atlas, _camera, _rect, _scale, _at), do: []

  defp sprite_placements(%__MODULE__{} = state, atlas, camera, rect, scale, at) do
    {ox, oy} = exact_origin(camera)

    state.movers
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{art, {x, y}}, index} ->
      {column, row, x_offset, y_offset} = Scale.place(scale, {x - ox, y - oy})

      if inside?(rect, column, row) do
        [
          ANSI.cursor_to(rect.x + column + 1, rect.y + row + 1),
          Kitty.place(Sprites.image_id(atlas, art, at),
            z: @sprite_layer,
            placement: index,
            x_offset: x_offset,
            y_offset: y_offset
          )
        ]
      else
        []
      end
    end)
  end

  defp inside?(rect, column, row),
    do: column >= 0 and column < rect.width and row >= 0 and row < rect.height

  @label_placement_base 10_000

  defp label_placements(%__MODULE__{labels: []}, _atlas, _camera, _rect, _scale), do: []

  defp label_placements(%__MODULE__{} = state, atlas, camera, rect, scale) do
    {:magnify, times} = scale.factor
    {ox, oy} = exact_origin(camera)

    state.labels
    |> Enum.with_index(@label_placement_base)
    |> Enum.flat_map(fn {label, index} ->
      {text, {x, y}, colour} = label_parts(label)
      font_scale = label_scale(label) * times
      {column, row, x_offset, y_offset} = Scale.place(scale, {x - ox, y - oy})

      if inside?(rect, column, row) do
        [
          label_stored(atlas, text, colour, font_scale, state.compress),
          ANSI.cursor_to(rect.x + column + 1, rect.y + row + 1),
          Kitty.place(Sprites.label_id(atlas, text, colour, font_scale),
            z: @sprite_layer,
            placement: index,
            x_offset: x_offset,
            y_offset: y_offset
          )
        ]
      else
        []
      end
    end)
  end

  defp label_scale({_text, _position, _colour}), do: 1
  defp label_scale({_text, _position, _colour, opts}), do: Keyword.get(opts, :scale, 1)

  defp label_stored(atlas, text, colour, scale, compress?) do
    id = Sprites.label_id(atlas, text, colour, scale)
    sent = Process.get({__MODULE__, :labels_sent}, MapSet.new())

    if MapSet.member?(sent, id) do
      []
    else
      Process.put({__MODULE__, :labels_sent}, MapSet.put(sent, id))
      Sprites.label_transmit(atlas, text, colour, scale, compress: compress?)
    end
  end

  defp pixel_labels(%__MODULE__{labels: []}, _camera), do: []

  defp pixel_labels(%__MODULE__{} = state, camera) do
    tile = Atlas.fetch(state.atlas).tile
    {ox, oy} = camera.origin

    Enum.map(state.labels, fn
      {text, {x, y}, colour} -> {text, {(x - ox) * tile, (y - oy) * tile}, colour}
      {text, {x, y}, colour, opts} -> {text, {(x - ox) * tile, (y - oy) * tile}, colour, opts}
    end)
  end

  defp pixel_movers(%__MODULE__{movers: []}, _camera), do: []

  defp pixel_movers(%__MODULE__{} = state, camera) do
    tile = Atlas.fetch(state.atlas).tile
    {ox, oy} = camera.origin

    Enum.map(state.movers, fn {art, {x, y}} -> {art, {(x - ox) * tile, (y - oy) * tile}} end)
  end

  defp serialize(raster, protocol, fit, id, compress?) do
    FrenchCurve.frame(raster, id, fit: fit, compress: compress?, protocol: protocol) ||
      {"", "", nil}
  end
end
