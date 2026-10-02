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
    * `:movers` — `[{art, {x, y}}]` or `[{art, {x, y}, heading}]` in world tile
      coordinates, which may be fractional, `heading` in radians. Default `[]`. In pixel
      mode a mover the size of a tile is drawn at its exact pixel position and a larger one
      stands in that cell, centred across it with its bottom edge on the cell's bottom, as
      `Cauldron2D.Surface` stands a tall overlay; in text mode it replaces the
      glyph of the nearest whole cell; every projection but the plain glyph one poses it
      by its heading, showing the art's `:front`, `:back` or `:side` and mirroring it when
      it faces left
    * `:volumes` — `[%{at: {x, y}, shape: shape, colour: {red, green, blue}, strength: s}]`
      in world tile coordinates: coloured regions of space tinting what is seen through
      them, as `Cauldron2D.Projection.Volume` describes them. Every projection draws
      them, and in text mode they tint the glyphs they cover. Default `[]`
    * `:labels` — `[{text, {x, y}, colour}]` or `[{text, {x, y}, colour, opts}]` in world
      tile coordinates, as `Cauldron2D.Surface.compose/4` takes them: names, numbers,
      notes drawn over everything. Default `[]`. In pixel mode a label is drawn in
      `Linocut.Font` at its exact pixel position, with placements as a stored image of its
      own; in text mode its characters overlay the glyphs from the nearest cell
    * `:zoom` — how many times its native size a tile is drawn: `2` twice as large,
      `0.5` half, so a pane shows half or twice the tiles. Default `1`. Levels a
      surface draws exactly are `zoom_levels/2`'s; another is drawn at the nearest of
      them. Zoomed in, a pixel terminal that can fit an image to cells is sent the
      smaller picture to scale, sixels are scaled first; zoomed out, the frame is
      composed at the lower resolution. In text mode a tile zoomed in covers that many
      more cells; zoomed out, every that-manyeth tile is drawn. Movers are placed by
      the terminal (placements) only at native size
    * `:mode` — a `Cauldron2D.Renderer` mode to force instead of detecting one;
      `:braille`: the frame composed at four dots per tile side, pixels at or above a
      luminance of 64 lit, drawn as braille text in the colour of each cell's lit pixels;
      or a `FrenchCurve.Backend.Cells` glyph set, `:half`, `:quad`, `:sextant` or
      `:octant`: the frame composed at twice the set's pixels per cell across a tile,
      drawn as block characters in two colours per cell. Default `nil`
    * `:compress` — zlib the kitty transmit. Default `true`
    * `:placements` — `:auto` (default), `true` or `false`. Whether the pane is drawn
      from images the terminal stores between frames rather than one image composited
      every  frame; see below
    * `:projection` — `:top` (default), `:iso` or `:first_person`; see below
    * `:facing` — which step of a turn the isometric view is at, `0` to `facings - 1`.
      A fraction is allowed and turns the view by part of a step. Default `0`
    * `:facings` — how many steps make a full turn, as a number for the isometric view or
      a map per projection, `%{iso: 8, oblique: 4}`. The oblique view is fixed at its
      default of one step, and takes `1` or `4`. For the isometric view, at least `4`.
      At `4` the view is drawn by blitting one stamp per art, which is the cheapest
      path; any other number, or a fractional `:facing`, draws the ground and the
      standing arts by sampling, which costs several times as much and is seamless at
      every angle. Default `4`
    * `:tilt` — the isometric diamond's height as a fraction of the tile, `0.5..1.5`.
      Default `1.0`
    * `:heading` — radians, where the first-person eye looks, `0` along `+x`. Default `0.0`
    * `:eye` — how far above the ground the camera sits, in tiles, where the projection
      puts it in the world: first person and mode 7. An art gives its own with
      `Cauldron2D.Atlas.eye_height/2`, so a taller figure sees further over the world.
      Default `nil`, the projection's own
    * `:pitch` — `-1.0..1.0`, how far the first-person horizon is moved. Default `0.0`
    * `:density` — how many pixels a terminal cell is drawn with in a projected view on a
      terminal that scales pictures to cells, before the zoom divides it. More pixels show
      more of a sprite's own detail; what that costs depends on the projection, because the
      isometric and oblique views blit whole sprites while first person and mode 7 sample
      every pixel. A map from projection to number sets each separately, which is how a game
      keeps a crisp isometric view without paying for it in first person. Default: half the
      atlas's tile size, and `4` in first person and mode 7
    * `:on_geometry` — an event name sent to the application whenever the pane's rect changes,
      see `on_rect_change/2`. Default `nil`
    * `:image_throttle`, `:image_priority` — how often a new frame is composed and at
      what scheduler priority, as drafter's widget server takes them. Defaults: every
      second application frame, `:low`. A game animating at the application's frame rate
      passes `image_throttle: {1, :tick}, image_priority: :normal`

  ## Projections

  `:iso` draws `Cauldron2D.Projection.Iso` with the focus at the pane's centre: floors as
  diamonds, arts with a `height` as blocks, movers and flat overlays upright, turned by
  `:facing` and tilted by `:tilt`; zoomed out it shrinks the whole picture. `:first_person`
  draws `Cauldron2D.Projection.FirstPerson` from the focus along `:heading`, with
  `:pitch`. Both are drawn as an image on a pixel terminal and as block characters or
  braille otherwise; plain glyphs (`:text`) stay top-down. Placements are not used.
  `world_at/3` maps a pane cell back to the ground for the top and isometric views.

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
  the grid is one stored image, fitted to the pane by the terminal and sent again only
  when its tiles or the atlas change, and each mover is a placement of a sprite stored by
  `Cauldron2D.Drafter.Sprites.transmit/2` — a few dozen bytes per mover per frame, no
  pixels. The surface stores the sprites itself, once per atlas and cell size, resampled
  to the two cells by one row a tile occupies, so the terminal draws a sprite pixel for
  pixel wherever it is placed. Elsewhere the movers are composited into one image per
  frame.

  The isometric and oblique panes are placed the same way while no volume is up: the pane
  is stored once at a quarter again its size, and a frame that only moved the camera
  shows that same image through a shifted source rectangle. Everything that moves is a
  patch — a small picture of the pane's own pixels around each mover, composed the way the
  whole frame is, so a mover behind a pillar is behind it in the patch too. Patches that
  touch are sent as one, and a frame whose moving parts cover too much of the pane is
  composited whole instead.

  The protocol is `protocol/1`'s; whether the terminal places is
  `FrenchCurve.Capability.placements?/1` asked of the session's environment, so an iTerm2
  drawing with kitty graphics, which stores but never places, is composited every frame.
  """

  use Drafter.Widget, handles: []

  require Logger

  alias Cauldron2D.{Atlas, Camera, Parallax, Renderer, Surface}
  alias Cauldron2D.Drafter.Sprites
  alias Cauldron2D.Drafter.Surface.Patch
  alias Cauldron2D.Projection.{FirstPerson, Glyphs, Iso, Mode7, Oblique, Volume}
  alias Drafter.Draw.{Segment, Strip}
  alias Drafter.Session.Context
  alias Drafter.Terminal.ANSI
  alias Drafter.Widget.Chart.Pixel
  alias FrenchCurve.Backend.{Braille, Cells, Kitty}
  alias FrenchCurve.Capability
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
    volumes: [],
    layers: [],
    mode: nil,
    zoom: 1,
    compress: true,
    placements: :auto,
    projection: :top,
    facing: 0,
    tilt: 1.0,
    heading: 0.0,
    pitch: 0.0,
    facings: 4,
    density: nil,
    eye: nil
  ]

  @projections [:top, :oblique, :iso, :mode7, :first_person]

  @braille_dots 4
  @braille_luminance 64
  @cell_sets [:half, :quad, :sextant, :octant]
  @fitted [:kitty, :iterm2]
  @sampled [:first_person, :mode7]
  @sampled_density 4
  @panned [:iso, :oblique]
  @zoom_in [4, 2]
  @zoom_out [2, 4, 8, 16]

  @doc """
  The zoom levels a surface draws exactly, largest first: in `:text` mode and the pixel
  modes (`:kitty`, `:iterm2`, `:sixel`, or `nil` for whichever is detected) 4 down to a
  sixteenth, kept to the divisors of the atlas's tile size zoomed out; in `:braille` mode
  those where a tile is a whole number of dots, from the tile's size in dots down to one.

  Those are the top-down projection's, and `zoom_levels/3` gives another projection's:
  isometric, 2 down to a quarter; oblique, 2 down to a half; first person and mode 7,
  `1` alone. The isometric view draws its own world smaller to zoom out, so its steps
  out cost nothing; see `fitted/1`.
  """
  @spec zoom_levels(Atlas.name(), atom() | nil) :: [number()]
  def zoom_levels(atlas, mode), do: zoom_levels(atlas, mode, :top)

  @doc "The zoom levels the surface draws `projection` at exactly, largest first; see `zoom_levels/2`."
  @spec zoom_levels(Atlas.name(), atom() | nil, atom()) :: [number()]
  def zoom_levels(_atlas, _mode, :iso), do: [2, 1, 0.5, 0.25]
  def zoom_levels(_atlas, _mode, :oblique), do: [2, 1, 0.5]

  def zoom_levels(atlas, :text, projection) when projection in [:first_person, :mode7],
    do: zoom_levels(atlas, :text, :top)

  def zoom_levels(_atlas, _mode, projection) when projection in [:first_person, :mode7], do: [1]

  def zoom_levels(atlas, mode, :top) do
    tile = Atlas.fetch(atlas).tile

    case mode do
      :braille ->
        for divisor <- divisors(tile), do: tile / (@braille_dots * divisor)

      set when set in @cell_sets ->
        {sx, _sy} = Cells.subpixels(set)
        for divisor <- divisors(tile), do: tile / (2 * sx * divisor)

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
      :volumes,
      :mode,
      :zoom,
      :compress,
      :placements,
      :layers,
      :on_geometry,
      :projection,
      :facing,
      :facings,
      :tilt,
      :heading,
      :pitch,
      :density,
      :eye
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
      volumes: Map.get(props, :volumes) || [],
      mode: Map.get(props, :mode),
      zoom: Map.get(props, :zoom) || 1,
      compress: Map.get(props, :compress, true),
      placements: Map.get(props, :placements, :auto),
      layers: Map.get(props, :layers, []),
      on_geometry: Map.get(props, :on_geometry),
      widget_id: Map.get(props, :id)
    }
    |> looking(props)
  end

  defp looking(state, props) do
    %{
      state
      | projection: Map.get(props, :projection) || :top,
        facing: Map.get(props, :facing) || 0,
        facings: Map.get(props, :facings) || 4,
        tilt: Map.get(props, :tilt) || 1.0,
        heading: Map.get(props, :heading) || 0.0,
        pitch: Map.get(props, :pitch) || 0.0,
        density: Map.get(props, :density),
        eye: Map.get(props, :eye)
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
        volumes: fold(props, :volumes, state.volumes) || [],
        atlas: fold(props, :atlas, state.atlas),
        mode: fold(props, :mode, state.mode),
        zoom: fold(props, :zoom, state.zoom) || 1,
        compress: fold(props, :compress, state.compress),
        placements: fold(props, :placements, state.placements),
        layers: fold(props, :layers, state.layers),
        on_geometry: fold(props, :on_geometry, state.on_geometry),
        density: fold(props, :density, state.density)
    }
    |> looked_at(props)
  end

  defp looked_at(state, props) do
    %{
      state
      | projection: fold(props, :projection, state.projection) || :top,
        facing: fold(props, :facing, state.facing) || 0,
        facings: fold(props, :facings, state.facings) || 4,
        tilt: fold(props, :tilt, state.tilt) || 1.0,
        heading: fold(props, :heading, state.heading) || 0.0,
        pitch: fold(props, :pitch, state.pitch) || 0.0,
        eye: fold(props, :eye, state.eye)
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

  def render(%__MODULE__{mode: set} = state, rect) when set in @cell_sets,
    do: cells(state, rect, set)

  def render(%__MODULE__{} = state, rect) do
    case protocol(state) do
      nil -> glyphs(state, rect)
      _pixel -> blank(rect, Atlas.fetch(state.atlas).void)
    end
  end

  @doc """
  The pixel protocol this surface draws with, or `nil` for glyphs.

  A forced `:mode` naming a protocol or a glyph rendering wins; then `CAULDRON_MODE` and
  the application configuration, through `Cauldron2D.Renderer.resolved/1`; and where
  those leave it to the terminal, `Drafter.Widget.Chart.Pixel.terminal/0`: what the
  session's terminal answered the startup probe, or its environment when it was not
  probed, with iTerm2 always judged by its environment.
  """
  @spec protocol(t()) :: :kitty | :iterm2 | :sixel | nil
  def protocol(%__MODULE__{mode: :braille}), do: nil
  def protocol(%__MODULE__{mode: set}) when set in @cell_sets, do: nil

  def protocol(%__MODULE__{mode: mode}) do
    case Renderer.resolved(mode) do
      :text -> nil
      :pixel -> Pixel.terminal()
      protocol -> protocol
    end
  end

  defp blank(rect, background) do
    width = max(rect.width, 1)
    strip = Strip.new([Segment.new(String.duplicate(" ", width), %{bg: background})])
    List.duplicate(strip, max(rect.height, 1))
  end

  defp glyphs(%__MODULE__{projection: projection} = state, rect) when projection in @panned do
    atlas = Atlas.fetch(state.atlas)
    columns = Camera.columns_for(rect.width)
    rows = Camera.rows_for(rect.height)
    zoom = nearest(state.zoom, zoom_levels(state.atlas, :text, projection))
    span = max(2, round(glyph_step(state, projection) / zoom))
    upright = %{state | zoom: 1}

    upright
    |> pane_opts({columns * span, rows * span})
    |> Keyword.put(:step, {span, span})
    |> then(&Glyphs.compose(state.atlas, projection_module(projection), &1))
    |> Enum.map(&lettered(&1, atlas.void, rect))
  end

  defp glyphs(%__MODULE__{} = state, rect) do
    atlas = Atlas.fetch(state.atlas)
    zoom = nearest(state.zoom, zoom_levels(state.atlas, :text))
    columns = Camera.columns_for(rect.width)
    rows = Camera.rows_for(rect.height)
    camera = glyph_camera(state, {columns, rows}, zoom)

    atlas
    |> Camera.glyphs(camera)
    |> magnify(zoom, {columns, rows})
    |> overlay_movers(atlas, camera, zoom, flat_movers(state))
    |> overlay_labels(camera, zoom, state.labels)
    |> overlay_volumes(camera, zoom, Volume.list(state.volumes))
    |> Enum.map(&lettered(&1, atlas.void, rect))
  end

  defp lettered(row, background, rect) do
    row
    |> Enum.map(fn {glyph, color} -> Segment.new(glyph, %{fg: color, bg: background}) end)
    |> Strip.new()
    |> Strip.fit_to_width(max(rect.width, 1))
  end

  defp glyph_step(state, projection) do
    module = projection_module(projection)
    probe = pane_opts(%{state | zoom: 1}, {64, 64})
    {fx, fy} = state.focus
    {_ox, oy} = module.project(state.atlas, {fx, fy}, probe)
    {_ax, ay} = module.project(state.atlas, {fx + 1, fy}, probe)
    {_bx, by} = module.project(state.atlas, {fx, fy + 1}, probe)

    max(2, round(abs(ay - oy) + abs(by - oy)))
  end

  defp projection_module(:iso), do: Iso
  defp projection_module(:oblique), do: Oblique

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

    state
    |> braille_raster(atlas, camera, {columns, cells}, {sx, sy}, scale)
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

  defp cells(%__MODULE__{} = state, rect, set) do
    atlas = Atlas.fetch(state.atlas)
    {sx, sy} = Cells.subpixels(set)
    dots = 2 * sx
    columns = Camera.columns_for(rect.width)
    rows = max(1, rect.height)
    zoom = nearest(state.zoom, zoom_levels(state.atlas, set))
    camera = view(state, rect, true, zoom)
    scale = round(atlas.tile / (dots * zoom))
    {scroll_x, scroll_y} = scroll_pixels(camera, atlas.tile)

    state
    |> cells_raster(atlas, camera, {columns, rows}, {dots, sy}, {scroll_x, scroll_y}, scale)
    |> FrenchCurve.render(:cells, set: set, background: atlas.void)
    |> Enum.map(fn row -> row |> Strip.from_cells() |> Strip.fit_to_width(max(rect.width, 1)) end)
  end

  defp cells_raster(
         %__MODULE__{projection: :top} = state,
         atlas,
         camera,
         {columns, rows},
         {dots, sy},
         {scroll_x, scroll_y},
         scale
       ) do
    target = {columns * dots, rows * dots}
    behind = parallax(state, target, scale, false)
    front = parallax(state, target, scale, true)

    atlas
    |> Surface.compose(camera.cells, pixel_movers(state, camera),
      scale: scale,
      at: now(),
      labels: pixel_labels(state, camera),
      volumes: grid_volumes(state, camera),
      void: void_mode(behind)
    )
    |> Raster.crop({div(scroll_x, scale), div(scroll_y, scale)}, target)
    |> under(behind)
    |> over_front(front)
    |> squash_rows(dots, sy)
  end

  defp cells_raster(state, _atlas, _camera, {columns, rows}, {dots, sy}, _scroll, _scale),
    do: projected(state, {columns * dots, rows * sy}, sy / dots)

  defp parallax(%__MODULE__{layers: []}, _target, _scale, _front), do: nil

  defp parallax(%__MODULE__{} = state, {width, height}, scale, front) do
    tile = max(1, div(tile(state), scale))

    Parallax.compose(state.atlas, state.layers,
      focus: state.focus,
      size: {width / tile, height / tile},
      pixels: {width, height},
      at: now(),
      scale: scale,
      front: front
    )
  end

  defp void_mode(nil), do: :opaque
  defp void_mode(_behind), do: :transparent

  defp under(raster, nil), do: raster
  defp under(raster, behind), do: Surface.stack(behind, raster)

  defp over_front(raster, nil), do: raster
  defp over_front(raster, front), do: Surface.stack(raster, front)

  defp squash_rows(raster, from, from), do: raster

  defp squash_rows(%Raster{width: width, height: height} = raster, from, to) do
    stride = width * 4
    rgba = Raster.to_rgba_binary(raster)
    target = div(height * to, from)

    rows =
      for row <- 0..(target - 1) do
        source = div(row * from, to)
        binary_part(rgba, source * stride, stride)
      end

    Raster.from_rgba(width, target, IO.iodata_to_binary(rows))
  end

  defp braille_raster(
         %__MODULE__{projection: :top} = state,
         atlas,
         camera,
         {columns, cells},
         {sx, sy},
         scale
       ) do
    target = {columns * @braille_dots, cells * @braille_dots}
    behind = parallax(state, target, scale, false)
    front = parallax(state, target, scale, true)

    atlas
    |> Surface.compose(camera.cells, pixel_movers(state, camera),
      scale: scale,
      at: now(),
      labels: pixel_labels(state, camera),
      volumes: grid_volumes(state, camera),
      void: void_mode(behind)
    )
    |> Raster.crop({div(sx, scale), div(sy, scale)}, target)
    |> under(behind)
    |> over_front(front)
  end

  defp braille_raster(state, _atlas, _camera, {columns, cells}, _scroll, _scale),
    do: projected(state, {columns * @braille_dots, cells * @braille_dots}, 1.0)

  defp lit_above(%Raster{} = raster, luminance) do
    keyed =
      for <<r, g, b, _a <- Raster.to_rgba_binary(raster)>>, into: <<>> do
        if r + g + b >= luminance * 3, do: <<r, g, b, 255>>, else: <<r, g, b, 0>>
      end

    Raster.from_rgba(raster.width, raster.height, keyed)
  end

  defp overlay_volumes(rows, _camera, _zoom, []), do: rows

  defp overlay_volumes(rows, camera, zoom, volumes) do
    {ox, oy} = camera.origin

    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, y} ->
      row
      |> Enum.with_index()
      |> Enum.map(fn {{glyph, colour}, x} ->
        {glyph, seen_through(colour, volumes, {ox + (x + 0.5) / zoom, oy + (y + 0.5) / zoom})}
      end)
    end)
  end

  defp seen_through(colour, volumes, {wx, wy}) do
    Enum.reduce(volumes, colour, fn volume, {red, green, blue} ->
      through = Volume.through(volume, {wx, wy, 0.0}, {0.0, 0.0, 1.0}, :infinity)
      <<tr, tg, tb, _>> = Volume.mix(<<red, green, blue, 255>>, volume, through)
      {tr, tg, tb}
    end)
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

  @doc "Whether `image/3` draws anything: a pixel protocol is in use and the view is set."
  @impl true
  @spec image_active?(t()) :: boolean()
  def image_active?(%__MODULE__{focus: nil}), do: false
  def image_active?(%__MODULE__{cell: nil}), do: false
  def image_active?(%__MODULE__{} = state), do: protocol(state) != nil

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

  defp encode(%__MODULE__{projection: projection} = state, rect, id, protocol)
       when projection != :top do
    columns = Camera.columns_for(rect.width)
    cells = max(1, rect.height)
    density = pixel_density(state, protocol)

    case patched(state, rect, id, protocol, columns, cells, density) do
      {:ok, frame} -> frame
      :whole -> whole_picture(state, id, protocol, columns, cells, density)
    end
  end

  defp encode(state, rect, id, protocol) do
    columns = Camera.columns_for(rect.width)
    cells = max(1, rect.height)
    zoom = nearest(state.zoom, zoom_levels(state.atlas, protocol))

    if zoom == 1 and placements?(state, protocol) do
      placed(state, rect, id, view(state, rect, true, 1), columns, cells)
    else
      raster = composed(state, rect, zoom, protocol, columns, cells)

      {paint, clear, place} =
        serialize(raster, protocol, {columns * 2, cells}, id, state.compress)

      {paint, clear, %{dx: 0, dy: 0, cols: columns * 2, rows: cells, place: place}}
    end
  end

  defp whole_picture(state, id, protocol, columns, cells, density) do
    raster =
      if protocol in @fitted,
        do: drawn(fitted(state), {columns * density, cells * density}, 1.0),
        else: projected(state, {columns * density, cells * density}, 1.0)

    {paint, clear, place} = serialize(raster, protocol, {columns * 2, cells}, id, state.compress)
    forget = forgotten(state, id)

    {[forget, paint], [forget, clear],
     %{dx: 0, dy: 0, cols: columns * 2, rows: cells, place: place}}
  end

  defp composed(state, rect, zoom, protocol, columns, cells) when zoom >= 1 do
    tile = tile(state)
    camera = view(state, rect, true, zoom)

    target = {round(columns * tile / zoom), round(cells * tile / zoom)}
    behind = parallax(state, target, 1, false)
    front = parallax(state, target, 1, true)

    raster =
      state.atlas
      |> Surface.compose(camera.cells, pixel_movers(state, camera),
        at: now(),
        labels: pixel_labels(state, camera),
        volumes: grid_volumes(state, camera),
        void: void_mode(behind)
      )
      |> Raster.crop(scroll_pixels(camera, tile), target)
      |> under(behind)
      |> over_front(front)

    if protocol == :sixel and zoom > 1, do: Surface.magnify(raster, round(zoom)), else: raster
  end

  defp composed(state, rect, zoom, _protocol, columns, cells) do
    tile = tile(state)
    scale = round(1 / zoom)
    camera = view(state, rect, true, zoom)
    {sx, sy} = scroll_pixels(camera, tile)

    target = {columns * tile, cells * tile}
    behind = parallax(state, target, scale, false)
    front = parallax(state, target, scale, true)

    state.atlas
    |> Surface.compose(camera.cells, pixel_movers(state, camera),
      scale: scale,
      at: now(),
      labels: pixel_labels(state, camera),
      volumes: grid_volumes(state, camera),
      void: void_mode(behind)
    )
    |> Raster.crop({div(sx, scale), div(sy, scale)}, target)
    |> under(behind)
    |> over_front(front)
  end

  defp tile(state), do: Atlas.fetch(state.atlas).tile

  @doc "The projections a surface draws: `:top`, `:iso` and `:first_person`."
  @spec projections() :: [atom()]
  def projections, do: @projections

  @doc """
  The world point under pane cell `{column, row}`, on the ground, for the view the
  surface draws; `nil` in first person, where a cell is not a place.
  """
  @spec world_at(t(), map(), {number(), number()}) :: {float(), float()} | nil
  def world_at(%__MODULE__{projection: projection} = state, rect, cell)
      when projection != :top do
    case picture(state, rect) do
      nil -> from_above(state, rect, cell)
      drawn -> looked_through(state, drawn, cell)
    end
  end

  def world_at(%__MODULE__{} = state, rect, cell), do: from_above(state, rect, cell)

  defp from_above(%__MODULE__{} = state, rect, {column, row}) do
    zoom = drawn_zoom(state)
    size = {Camera.columns_for(rect.width), Camera.rows_for(rect.height)}
    origin = Camera.exact_origin(state.focus, Camera.zoomed(size, zoom))
    Camera.tile_at(origin, {column, row}, zoom)
  end

  defp looked_through(state, {{width, height}, {across, down}, aspect}, {column, row}) do
    fitted? = protocol(state) in @fitted
    zoom = if fitted?, do: 1, else: fitting_zoom(state, height)
    at = {column * across / zoom, row * down / zoom}
    size = {max(1, round(width / zoom)), max(1, round(height / zoom))}
    state = if fitted?, do: fitted(state), else: %{state | zoom: zoom}

    case state.projection do
      :iso -> Iso.unproject(state.atlas, at, iso_opts(state, size, aspect))
      :oblique -> Oblique.unproject(state.atlas, at, oblique_opts(state, size, aspect))
      :mode7 -> Mode7.unproject(state.atlas, at, mode7_opts(state, size, aspect))
      :first_person -> nil
    end
  end

  @doc """
  The pane cell a world point is drawn at, as `world_at/3` reads one back.

  `{column, row}` relative to the pane's top-left corner, fractional, so a caller can see
  where in the cell the point falls. `nil` in first person, and for a point the
  projection cannot show. Round-trips with `world_at/3`.
  """
  @spec cell_at(t(), map(), {number(), number()}) :: {float(), float()} | nil
  def cell_at(%__MODULE__{projection: :first_person}, _rect, _world), do: nil

  def cell_at(%__MODULE__{projection: projection} = state, rect, world)
      when projection != :top do
    case picture(state, rect) do
      nil -> above_cell(state, rect, world)
      drawn -> drawn_cell(state, drawn, world)
    end
  end

  def cell_at(%__MODULE__{} = state, rect, world), do: above_cell(state, rect, world)

  defp above_cell(%__MODULE__{} = state, rect, {x, y}) do
    zoom = drawn_zoom(state)
    size = {Camera.columns_for(rect.width), Camera.rows_for(rect.height)}
    {ox, oy} = Camera.exact_origin(state.focus, Camera.zoomed(size, zoom))

    {(x - ox) * 2 * zoom - 0.5, (y - oy) * zoom - 0.5}
  end

  defp drawn_cell(state, {{width, height}, {across, down}, aspect}, world) do
    fitted? = protocol(state) in @fitted
    zoom = if fitted?, do: 1, else: fitting_zoom(state, height)
    size = {max(1, round(width / zoom)), max(1, round(height / zoom))}
    state = if fitted?, do: fitted(state), else: %{state | zoom: zoom}

    case projected_pixel(state, size, aspect, world) do
      nil -> nil
      {px, py} -> {px * zoom / across, py * zoom / down}
    end
  end

  defp projected_pixel(%__MODULE__{projection: :iso} = state, size, aspect, world),
    do: Iso.project(state.atlas, world, iso_opts(state, size, aspect))

  defp projected_pixel(%__MODULE__{projection: :oblique} = state, size, aspect, world),
    do: Oblique.project(state.atlas, world, oblique_opts(state, size, aspect))

  defp projected_pixel(%__MODULE__{projection: :mode7} = state, size, aspect, world),
    do: Mode7.project(state.atlas, world, mode7_opts(state, size, aspect))

  @doc """
  The picture a projection is drawn into for `rect`, in the mode the surface is in.

  `{{width, height}, {across, down}, aspect}`: the picture's size in pixels, how many of
  those pixels a terminal cell and a terminal row cover, and the pixel aspect the
  projection is given. `nil` in the plain glyph mode, which draws the grid from above
  whatever the projection is.
  """
  @spec picture(t(), map()) :: {{number(), number()}, {number(), number()}, number()} | nil
  def picture(%__MODULE__{} = state, rect) do
    columns = Camera.columns_for(rect.width)
    rows = max(1, rect.height)

    case drawn_mode(state) do
      :text ->
        nil

      :braille ->
        dots = @braille_dots
        {{columns * dots, rows * dots}, {dots / 2, dots}, 1.0}

      set when set in @cell_sets ->
        {sx, sy} = Cells.subpixels(set)
        dots = 2 * sx
        {{columns * dots, rows * sy}, {dots / 2, sy}, sy / dots}

      protocol ->
        density = pixel_density(state, protocol)
        {{columns * density, rows * density}, {density / 2, density}, 1.0}
    end
  end

  @doc """
  The mode the surface actually draws in: a cell set, `:braille`, a pixel protocol, or
  `:text` where there is no picture to draw.
  """
  @spec drawn_mode(t()) :: atom()
  def drawn_mode(%__MODULE__{mode: :braille}), do: :braille
  def drawn_mode(%__MODULE__{mode: set}) when set in @cell_sets, do: set
  def drawn_mode(%__MODULE__{} = state), do: protocol(state) || :text

  defp drawn_zoom(%__MODULE__{} = state),
    do: nearest(state.zoom, zoom_levels(state.atlas, drawn_mode(state)))

  @doc """
  The surface as a picture protocol draws it: zooming in is fewer pixels for the same
  cells, and zooming out, where the projection can draw its own world smaller, is the
  same pixels with a smaller world in them.

  A terminal that scales pictures to cells has no other way to zoom in than to hand it a
  smaller picture. Zooming out that way costs four times the pixels a step, which is a
  picture nobody can transmit thirty times a second; a projection that takes a `:shrink`
  draws more world into the picture it already had instead.
  """
  @spec fitted(t()) :: t()
  def fitted(%__MODULE__{} = state) do
    zoom = projection_zoom(state)
    %{state | zoom: if(shrinks?(state.projection), do: min(zoom, 1), else: 1)}
  end

  defp shrinks?(projection), do: projection == :iso

  defp pixel_density(state, protocol) when protocol in @fitted do
    zoom = projection_zoom(state)
    asked = if shrinks?(state.projection), do: max(zoom, 1), else: zoom

    max(1, round(native_density(state) / asked))
  end

  defp pixel_density(state, _protocol), do: tile(state)

  defp native_density(%__MODULE__{projection: projection} = state),
    do: asked_density(state.density, projection) || default_density(state, projection)

  defp asked_density(nil, _projection), do: nil
  defp asked_density(density, projection) when is_map(density), do: Map.get(density, projection)
  defp asked_density(density, _projection), do: density

  defp default_density(_state, projection) when projection in @sampled, do: @sampled_density
  defp default_density(state, _projection), do: tile(state) / 2

  @doc """
  The zoom a projection is actually drawn at in a picture `height` pixels tall.

  The zoom asked for, rounded to a level the projection draws exactly, then pulled back
  until the tallest art stands in the half of the picture above its feet with a tile to
  spare, so a figure at the middle of the picture has room over its head. In the cell and
  braille modes a picture is only a few dozen pixels tall, so the closest zoom would
  otherwise show a figure's boots and nothing above them.
  """
  @spec fitting_zoom(t(), pos_integer()) :: number()
  def fitting_zoom(%__MODULE__{} = state, height) do
    levels = zoom_levels(state.atlas, drawn_mode(state), state.projection)
    wanted = nearest(state.zoom, levels)
    room = 2 * (Atlas.tallest(state.atlas) + Atlas.fetch(state.atlas).tile)

    levels
    |> Enum.filter(&(&1 <= wanted))
    |> Enum.find(List.last(levels), &(height / &1 >= room))
  end

  defp projected(state, {width, height}, aspect) do
    zoom = fitting_zoom(state, height)
    state = %{state | zoom: zoom}

    case zoom do
      zoom when zoom > 1 ->
        state
        |> drawn({ceil(width / zoom), ceil(height / zoom)}, aspect)
        |> Surface.magnify(round(zoom))
        |> Raster.crop({0, 0}, {width, height})

      _native_or_out ->
        drawn(state, {width, height}, aspect)
    end
  end

  defp projection_zoom(%__MODULE__{} = state),
    do: nearest(state.zoom, zoom_levels(state.atlas, drawn_mode(state), state.projection))

  defp drawn(%__MODULE__{projection: :iso} = state, size, aspect) do
    Iso.compose(state.atlas, iso_opts(state, size, aspect))
  end

  defp drawn(%__MODULE__{projection: :oblique} = state, size, aspect) do
    Oblique.compose(state.atlas, oblique_opts(state, size, aspect))
  end

  defp drawn(%__MODULE__{projection: :mode7} = state, size, aspect) do
    Mode7.render(state.atlas, mode7_opts(state, size, aspect))
  end

  defp drawn(%__MODULE__{projection: :first_person} = state, size, aspect) do
    FirstPerson.render(
      state.atlas,
      [
        position: state.focus,
        heading: state.heading,
        pitch: state.pitch,
        cell: state.cell,
        size: size,
        aspect: aspect,
        movers: state.movers,
        volumes: state.volumes,
        at: now()
      ] ++ from_eye(state)
    )
  end

  defp from_eye(%__MODULE__{eye: nil}), do: []
  defp from_eye(%__MODULE__{eye: eye}), do: [eye: eye]

  defp iso_opts(state, size, aspect) do
    [
      focus: state.focus,
      cell: state.cell,
      size: size,
      facing: state.facing,
      facings: facings_for(state, :iso),
      tilt: state.tilt * aspect,
      shrink: iso_shrink(projection_zoom(state)),
      movers: state.movers,
      labels: state.labels,
      volumes: state.volumes,
      at: now()
    ]
  end

  defp oblique_opts(state, size, aspect) do
    [
      focus: state.focus,
      cell: state.cell,
      size: size,
      squash: 0.5 * aspect,
      facing: state.facing,
      facings: facings_for(state, :oblique),
      movers: state.movers,
      labels: state.labels,
      volumes: state.volumes,
      at: now()
    ]
  end

  defp mode7_opts(state, size, aspect) do
    [
      position: state.focus,
      heading: state.heading,
      pitch: state.pitch,
      cell: state.cell,
      size: size,
      aspect: aspect,
      movers: state.movers,
      volumes: state.volumes,
      at: now()
    ] ++ from_eye(state)
  end

  defp facings_for(%__MODULE__{facings: facings}, projection) when is_map(facings),
    do: Map.get(facings, projection, default_facings(projection))

  defp facings_for(%__MODULE__{}, :oblique), do: default_facings(:oblique)
  defp facings_for(%__MODULE__{facings: facings}, _projection), do: facings

  defp default_facings(:oblique), do: 1
  defp default_facings(_projection), do: 4

  defp iso_shrink(zoom) when zoom >= 1, do: 1
  defp iso_shrink(zoom), do: min(4, max(1, round(1 / zoom)))

  defp flat_movers(%__MODULE__{movers: movers}) do
    Enum.map(movers, fn
      {art, position} -> {art, position}
      {art, position, _heading} -> {art, position}
    end)
  end

  defp placements?(%__MODULE__{layers: [_ | _]}, _protocol), do: false
  defp placements?(%__MODULE__{placements: false}, _protocol), do: false
  defp placements?(%__MODULE__{placements: true}, :kitty), do: Context.cell_size() != nil

  defp placements?(%__MODULE__{placements: :auto}, :kitty) do
    Context.cell_size() != nil and session_placements?()
  end

  defp placements?(_state, _protocol), do: false

  defp session_placements?, do: Capability.placements?(Context.terminal_env())

  @sprite_layer 1

  defp scroll_pixels(%Camera{scroll: {sx, sy}}, tile), do: {round(sx * tile), round(sy * tile)}
  defp exact_origin(%Camera{origin: {ox, oy}, scroll: {sx, sy}}), do: {ox + sx, oy + sy}

  defp now, do: System.monotonic_time(:millisecond)

  defp placed(state, rect, id, camera, columns, cells) do
    atlas = Atlas.fetch(state.atlas)
    at = now()
    volumes = grid_volumes(state, camera)
    image = FrenchCurve.image_id(id)
    {sx, sy} = scroll_pixels(camera, atlas.tile)

    place =
      Kitty.place(image,
        placement: 1,
        fit: {columns * 2, cells},
        source: {sx, sy, columns * atlas.tile, cells * atlas.tile}
      )

    clear = Kitty.delete(id: image, placement: 1)

    background =
      background_bytes(
        atlas,
        id,
        {camera.cells, animation_frames(atlas, at), volumes},
        place,
        fn ->
          grid = Surface.compose(atlas, camera.cells, [], at: at, volumes: volumes)
          [clear, Kitty.transmit(grid, image, compress: state.compress), place]
        end
      )

    layer =
      sprite_placements(state, atlas, camera, rect, columns, cells, at) ++
        label_placements(state, atlas, camera, rect, columns, cells)

    {[sprites_stored(state, atlas), background, layer], [clear, Kitty.delete(z: @sprite_layer)],
     %{dx: 0, dy: 0, cols: columns * 2, rows: cells, place: IO.iodata_to_binary([place, layer])}}
  end

  defp sprites_stored(state, atlas) do
    {cell_width, cell_height} = Context.cell_size()
    size = {2 * cell_width, cell_height}
    key = {__MODULE__, :sprites_sent}

    if Process.get(key) == {atlas, size} do
      []
    else
      Process.put(key, {atlas, size})
      Sprites.transmit(atlas, size: size, compress: state.compress)
    end
  end

  defp background_bytes(atlas, id, cells, place, paint) do
    table = Atlas.cache(atlas.name)
    key = {:background, id}
    digest = :erlang.phash2(cells)

    case :ets.lookup(table, key) do
      [{^key, ^digest}] when place != nil ->
        place

      _changed ->
        :ets.insert(table, {key, digest})
        paint.()
    end
  end

  defp animation_frames(atlas, at) do
    for art <- Atlas.arts(atlas),
        Atlas.animated?(atlas, art),
        do: {art, Atlas.frame_index(atlas, art, at)}
  end

  defp sprite_placements(
         %__MODULE__{movers: []} = state,
         atlas,
         _camera,
         _rect,
         _cols,
         _rows,
         _at
       ),
       do: retired(atlas, state.widget_id, [])

  defp sprite_placements(%__MODULE__{} = state, atlas, camera, rect, columns, cells, at) do
    {cell_width, cell_height} = Context.cell_size()
    {ox, oy} = exact_origin(camera)

    shown =
      state
      |> flat_movers()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {{art, {x, y}}, index} ->
        across = (x - ox) * 2
        down = y - oy
        column = floor(across)
        row = floor(down)

        if column >= 0 and column < columns * 2 and row >= 0 and row < cells do
          image = Sprites.image_id(atlas, art, at)

          [
            {{image, index},
             [
               ANSI.cursor_to(rect.x + column + 1, rect.y + row + 1),
               Kitty.place(image,
                 fit: {2, 1},
                 z: @sprite_layer,
                 placement: index,
                 x_offset: round((across - column) * cell_width),
                 y_offset: round((down - row) * cell_height)
               )
             ]}
          ]
        else
          []
        end
      end)

    retired(atlas, state.widget_id, Enum.map(shown, &elem(&1, 0))) ++
      Enum.map(shown, &elem(&1, 1))
  end

  defp retired(atlas, id, placed) do
    table = Atlas.cache(atlas.name)
    key = {:sprites, id}
    now = MapSet.new(placed)

    gone =
      case :ets.lookup(table, key) do
        [{^key, before}] -> MapSet.difference(before, now)
        [] -> MapSet.new()
      end

    :ets.insert(table, {key, now})

    for {image, placement} <- gone, do: Kitty.delete(id: image, placement: placement)
  end

  @label_placement_base 10_000

  defp label_placements(%__MODULE__{labels: []}, _atlas, _camera, _rect, _columns, _cells), do: []

  defp label_placements(%__MODULE__{} = state, atlas, camera, rect, columns, cells) do
    {cell_width, cell_height} = Context.cell_size()
    {ox, oy} = exact_origin(camera)

    state.labels
    |> Enum.with_index(@label_placement_base)
    |> Enum.flat_map(fn {label, index} ->
      {text, {x, y}, colour} = label_parts(label)
      scale = label_scale(label)
      across = (x - ox) * 2
      down = y - oy
      column = floor(across)
      row = floor(down)

      if column >= 0 and column < columns * 2 and row >= 0 and row < cells do
        [
          label_stored(atlas, text, colour, scale, state.compress),
          ANSI.cursor_to(rect.x + column + 1, rect.y + row + 1),
          Kitty.place(Sprites.label_id(atlas, text, colour, scale),
            z: @sprite_layer,
            placement: index,
            x_offset: round((across - column) * cell_width),
            y_offset: round((down - row) * cell_height)
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

  defp grid_volumes(%__MODULE__{volumes: []}, _camera), do: []

  defp grid_volumes(%__MODULE__{} = state, camera) do
    {ox, oy} = camera.origin

    Enum.map(state.volumes, fn volume ->
      volume = Map.new(volume)
      {x, y} = Map.fetch!(volume, :at)
      Map.put(volume, :at, {x - ox, y - oy})
    end)
  end

  defp pixel_movers(%__MODULE__{movers: []}, _camera), do: []

  defp pixel_movers(%__MODULE__{} = state, camera) do
    atlas = Atlas.fetch(state.atlas)
    tile = atlas.tile
    {ox, oy} = camera.origin

    Enum.map(state.movers, fn mover ->
      {art, {x, y}, heading} = with_heading(mover)
      {width, height} = Atlas.entry(atlas, art).size
      {pose, flip} = pose(heading)

      {art, {(x - ox) * tile + (tile - width) / 2, (y - oy) * tile + tile - height}, nil, pose,
       flip}
    end)
  end

  defp with_heading({art, position}), do: {art, position, nil}
  defp with_heading({art, position, heading}), do: {art, position, heading}

  defp pose(nil), do: {nil, false}

  defp pose(heading) do
    {across, down} = {:math.cos(heading), :math.sin(heading)}

    cond do
      down > 0.5 -> {:front, false}
      down < -0.5 -> {:back, false}
      true -> {:side, across < 0}
    end
  end

  @patch_layer 2
  @patch_base 20_000
  @patch_room 0.45
  @patch_limit 10
  @scene_placement 1
  @churn_limit 3
  @churn_rest 1_000
  @pan_margin 0.25

  defp patched(
         %__MODULE__{projection: projection, volumes: []} = state,
         rect,
         id,
         :kitty,
         columns,
         cells,
         density
       )
       when projection in @panned do
    if placements?(state, :kitty) and rem(density, 2) == 0 do
      drawing(fitted(state), rect, id, columns, cells, density)
    else
      :whole
    end
  end

  defp patched(_state, _rect, _id, _protocol, _columns, _cells, _density), do: :whole

  defp drawing(state, rect, id, columns, cells, density) do
    pane = {columns * density, cells * density}
    grid = {div(density, 2), density}
    opts = pane_opts(state, pane)

    case Patch.plan(moving_spots(state, opts), pane, grid, @patch_room) do
      {:patches, rects} when length(rects) <= @patch_limit ->
        layered(state, rect, id, opts, %{
          pane: pane,
          grid: grid,
          rects: rects,
          columns: columns,
          cells: cells
        })

      _too_much ->
        :whole
    end
  end

  defp layered(state, rect, id, opts, %{pane: {pane_w, pane_h} = pane} = cut) do
    %{grid: grid, rects: rects, columns: columns, cells: cells} = cut
    atlas = Atlas.fetch(state.atlas)
    image = FrenchCurve.image_id({id, :scene})
    size = {pane_w + 2 * round(pane_w * @pan_margin), pane_h + 2 * round(pane_h * @pan_margin)}

    case scene(state, atlas, id, image, opts, size, pane) do
      :churning ->
        :whole

      {sent, {sx, sy}} ->
        place =
          Kitty.place(image,
            placement: @scene_placement,
            fit: {columns * 2, cells},
            source: {sx, sy, pane_w, pane_h}
          )

        {paint, places} = patches(state, rect, atlas, id, opts, grid, rects)

        {:ok,
         {[retired(atlas, state.widget_id, []), sent, place, paint],
          [Kitty.delete(id: image), Kitty.delete(z: @patch_layer), unplace_sprites()],
          %{
            dx: 0,
            dy: 0,
            cols: columns * 2,
            rows: cells,
            place: IO.iodata_to_binary([place, places])
          }}}
    end
  end

  defp scene(state, atlas, id, image, opts, size, pane) do
    table = Atlas.cache(atlas.name)
    key = {:scene, id}

    case table |> :ets.lookup(key) |> reusable(state, atlas, image, opts, size, pane) do
      nil ->
        recomposed(state, atlas, table, key, image, opts, size, pane)

      source ->
        {settled(table, key), source}
    end
  end

  defp recomposed(state, atlas, table, key, image, opts, {wide, tall} = size, {pane_w, pane_h}) do
    case churned(table, key) do
      :rest ->
        :churning

      :compose ->
        fresh = scene_opts(opts, Keyword.fetch!(opts, :focus), size)
        raster = pane_compose(state, fresh)

        :ets.insert(
          table,
          {key, image, scene_digest(state, atlas, fresh, size), Keyword.fetch!(fresh, :focus)}
        )

        {[Kitty.delete(id: image), Kitty.transmit(raster, image, compress: state.compress)],
         {div(wide - pane_w, 2), div(tall - pane_h, 2)}}
    end
  end

  defp reusable([{_key, image, digest, focus}], state, atlas, image, opts, size, pane) do
    stored = scene_opts(opts, focus, size)
    source = source_of(state, stored, pane)

    if within?(source, size, pane) and digest == scene_digest(state, atlas, stored, size),
      do: source,
      else: nil
  end

  defp reusable(_gone, _state, _atlas, _image, _opts, _size, _pane), do: nil

  defp within?({sx, sy}, {wide, tall}, {pane_w, pane_h}),
    do: sx >= 0 and sy >= 0 and sx + pane_w <= wide and sy + pane_h <= tall

  defp settled(table, key) do
    :ets.delete(table, churn_key(key))
    []
  end

  defp churned(table, key) do
    churn = churn_key(key)

    case :ets.lookup(table, churn) do
      [{^churn, _count, until}] when until > 0 ->
        if now() < until, do: :rest, else: started(table, churn)

      [{^churn, count, _until}] when count + 1 >= @churn_limit ->
        :ets.insert(table, {churn, 0, now() + @churn_rest})
        :rest

      [{^churn, count, _until}] ->
        :ets.insert(table, {churn, count + 1, 0})
        :compose

      [] ->
        started(table, churn)
    end
  end

  defp started(table, churn) do
    :ets.insert(table, {churn, 1, 0})
    :compose
  end

  defp churn_key({:scene, id}), do: {:scene_churn, id}

  defp scene_digest(state, atlas, opts, size) do
    cells = pane_cells(state, opts)

    :erlang.phash2({
      cells,
      scenery_frames(atlas, cells, Keyword.get(opts, :at, 0)),
      Keyword.get(opts, :facing),
      Keyword.get(opts, :facings),
      Keyword.get(opts, :tilt),
      Keyword.get(opts, :squash),
      Keyword.get(opts, :shrink),
      size,
      state.compress
    })
  end

  defp scenery_frames(atlas, cells, at) do
    cells
    |> Enum.reduce(MapSet.new(), fn {_position, {base, overlays, _tint}}, arts ->
      Enum.reduce([base | overlays], arts, &MapSet.put(&2, &1))
    end)
    |> Enum.filter(&Atlas.animated?(atlas, &1))
    |> Enum.map(&{&1, Atlas.frame_index(atlas, &1, at)})
  end

  defp pane_cells(%__MODULE__{projection: :iso} = state, opts), do: Iso.cells(state.atlas, opts)

  defp pane_cells(%__MODULE__{projection: :oblique} = state, opts),
    do: Oblique.cells(state.atlas, opts)

  defp source_of(state, opts, {pane_w, pane_h}) do
    {px, py} = pane_project(state, opts, state.focus)
    {round(px - pane_w / 2), round(py - pane_h / 2)}
  end

  defp scene_opts(opts, focus, size) do
    opts
    |> Keyword.put(:size, size)
    |> Keyword.put(:focus, focus)
    |> Keyword.put(:movers, [])
    |> Keyword.put(:labels, [])
  end

  defp patches(state, rect, atlas, id, opts, {across, down}, rects) do
    shown =
      rects
      |> Enum.with_index(@patch_base)
      |> Enum.map(fn {{px, py, pw, ph}, placement} ->
        image = FrenchCurve.image_id({id, :patch, placement})
        focus = pane_unproject(state, opts, {px + pw / 2, py + ph / 2})

        raster =
          pane_compose(state, opts |> Keyword.put(:focus, focus) |> Keyword.put(:size, {pw, ph}))

        place = [
          ANSI.cursor_to(rect.x + div(px, across) + 1, rect.y + div(py, down) + 1),
          Kitty.place(image,
            fit: {div(pw, across), div(ph, down)},
            z: @patch_layer,
            placement: placement
          )
        ]

        {{image, placement},
         [
           Kitty.delete(id: image, placement: placement),
           Kitty.transmit(raster, image, compress: state.compress),
           place
         ], place}
      end)

    paint =
      retired(atlas, {id, :patches}, Enum.map(shown, &elem(&1, 0))) ++
        Enum.map(shown, &elem(&1, 1))

    {paint, Enum.map(shown, &elem(&1, 2))}
  end

  defp moving_spots(%__MODULE__{movers: [], labels: []}, _opts), do: []

  defp moving_spots(%__MODULE__{} = state, opts) do
    atlas = Atlas.fetch(state.atlas)
    rise = (Atlas.tallest(atlas) + atlas.tile) / pane_shrink(state)

    movers = for {_art, position} <- flat_movers(state), do: spot(state, opts, position, rise)

    movers ++ for label <- state.labels, do: label_spot(state, opts, label)
  end

  defp label_spot(state, opts, label) do
    {text, position, colour} = label_parts(label)
    drawn = Linocut.Font.render(text, colour, scale: label_scale(label))
    {px, py} = pane_project(state, opts, position)

    {px - drawn.width / 2, py - drawn.height / 2, drawn.width, drawn.height}
  end

  defp spot(state, opts, {x, y}, rise) do
    corners =
      for dx <- [-0.6, 0.6], dy <- [-0.6, 0.6], do: pane_project(state, opts, {x + dx, y + dy})

    {left, right} = corners |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {top, bottom} = corners |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    {left, top - rise, right - left, bottom - top + rise}
  end

  defp pane_shrink(%__MODULE__{projection: :iso} = state), do: iso_shrink(projection_zoom(state))
  defp pane_shrink(_state), do: 1

  defp pane_opts(%__MODULE__{projection: :iso} = state, size), do: iso_opts(state, size, 1.0)

  defp pane_opts(%__MODULE__{projection: :oblique} = state, size),
    do: oblique_opts(state, size, 1.0)

  defp pane_compose(%__MODULE__{projection: :iso} = state, opts),
    do: Iso.compose(state.atlas, opts)

  defp pane_compose(%__MODULE__{projection: :oblique} = state, opts),
    do: Oblique.compose(state.atlas, opts)

  defp pane_project(%__MODULE__{projection: :iso} = state, opts, world),
    do: Iso.project(state.atlas, world, opts)

  defp pane_project(%__MODULE__{projection: :oblique} = state, opts, world),
    do: Oblique.project(state.atlas, world, opts)

  defp pane_unproject(%__MODULE__{projection: :iso} = state, opts, pixel),
    do: Iso.unproject(state.atlas, pixel, opts)

  defp pane_unproject(%__MODULE__{projection: :oblique} = state, opts, pixel),
    do: Oblique.unproject(state.atlas, pixel, opts)

  defp forgotten(%__MODULE__{} = state, id) do
    atlas = Atlas.fetch(state.atlas)
    table = Atlas.cache(atlas.name)
    key = {:scene, id}

    dropped =
      case :ets.lookup(table, key) do
        [{^key, image, _digest, _focus}] ->
          :ets.delete(table, key)
          [Kitty.delete(id: image)]

        _none ->
          []
      end

    :ets.delete(table, churn_key(key))

    dropped ++ retired(atlas, {id, :patches}, [])
  end

  defp serialize(raster, protocol, fit, id, compress?) do
    placements = Capability.placements?(Context.terminal_env())

    case FrenchCurve.frame(raster, id,
           fit: fit,
           compress: compress?,
           protocol: protocol,
           placements: placements
         ) do
      nil ->
        {"", "", nil}

      {paint, clear, place} when protocol == :kitty and placements ->
        {[unplace_sprites(), paint], [unplace_sprites(), clear], place}

      frame ->
        frame
    end
  end

  defp unplace_sprites, do: Kitty.delete(z: @sprite_layer)
end
