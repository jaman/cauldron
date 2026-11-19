defmodule Cauldron2D.Draw do
  @moduledoc """
  A scene drawn as one picture: the world from the atlas in its projection, its
  parallax layers, movers, labels and volumes, and over them its `:screen` and
  `:outlines` — every front end's picture of a `c:Cauldron.Client.Game.scene/1`.

      view = Cauldron2D.Draw.new(Cauldron2D.Draw.props(MyGame.Client, scene, look, 1))
      raster = Cauldron2D.Draw.picture(view, {40, 22})

  `props/4` turns a game's scene and the client's look into a view's props; `new/1`
  makes the view. `picture/3` draws it over a pane `{columns, rows}` tiles of the
  atlas at zoom 1, as a `Cauldron2D.Raster` the front end scales to its pane: the
  top-down view one atlas pixel to a raster pixel (fewer at a zoom in, more at a zoom
  out), the projections at `density/2` pixels a tile, a `:picture` at its own size.

  The functions below `picture/3` are its parts, for a front end that draws some of
  them its own way (the terminal's stored images and glyphs). `mode` is the display
  mode zoom levels are chosen for: `:kitty`, `:iterm2` or `:sixel` for a picture a
  terminal shows, `:text`, `:braille` or a cell set for glyphs; a window or a
  browser draws as `:kitty` does, a picture scaled to the pane.

  ## View

  A view holds the props `Cauldron2D.Drafter.Surface` documents: `:atlas`, `:focus`,
  `:cell`, `:movers`, `:labels`, `:screen`, `:outlines`, `:volumes`, `:layers`,
  `:zoom`, `:projection`, `:facing`, `:facings`, `:tilt`, `:heading`, `:pitch`,
  `:density`, `:eye`, `:picture` and `:native`. A view with a `:picture` has
  projection `:picture`.
  """

  alias Cauldron2D.{Atlas, Camera, Field, Heading, Parallax, Raster, Screen, Surface}
  alias Cauldron2D.Projection.{FirstPerson, Iso, Mode7, Oblique}
  alias FrenchCurve.Backend.Cells

  @type t :: %__MODULE__{}

  defstruct [
    :atlas,
    :focus,
    :cell,
    :density,
    :eye,
    :picture,
    :native,
    movers: [],
    labels: [],
    screen: [],
    outlines: [],
    volumes: [],
    layers: [],
    zoom: 1,
    projection: :top,
    facing: 0,
    facings: 4,
    tilt: 1.0,
    heading: 0.0,
    pitch: 0.0
  ]

  @projections [:top, :oblique, :iso, :mode7, :first_person]
  @braille_dots 4
  @cell_sets [:half, :quad, :sextant, :octant]
  @sampled [:first_person, :mode7, :picture]
  @sampled_density 4
  @fitted [:kitty, :iterm2]
  @zoom_in [4, 2]
  @zoom_out [2, 4, 8, 16]

  @doc """
  A view from props, a map or keyword list; every prop absent or `nil` takes its default.
  Movers and `:heading` may name their headings (`Cauldron2D.Heading`).
  """
  @spec new(map() | keyword()) :: t()
  def new(props) do
    present = props |> Map.new() |> Map.reject(fn {_key, value} -> is_nil(value) end)

    __MODULE__
    |> struct(present)
    |> in_radians()
    |> picture_projection()
  end

  @doc """
  A view's props from `game`'s `scene` and the client's `look` (`:projection`,
  `:facing`, `:facings`, `:tilt`, `:heading`, `:pitch`, `:density`), at `zoom`.
  The scene's own `:heading` wins over the look's; its `:eye` is read by `eye_height/2`.
  Its movers and `:heading` may name their headings, given on in radians
  (`Cauldron2D.Heading`).
  A 3D scene's `:gpu` and `:gpu_size` are passed on as they are, for a drawer that
  sends 3D scenes (`Cauldron3D.Net.Drawer`). A scene with a `:field` seen top-down is
  drawn as `Cauldron2D.Field.scene/3` makes it.
  """
  @spec props(module(), map(), map(), number()) :: keyword()
  def props(game, scene, look, zoom) do
    scene = Field.scene(scene, game.atlas(), Map.get(look, :projection, :top))

    [
      atlas: game.atlas(),
      focus: scene[:focus],
      zoom: zoom,
      cell: scene[:cell],
      movers: Heading.movers(scene[:movers] || []),
      labels: Map.get(scene, :labels, []),
      screen: Map.get(scene, :screen, []),
      outlines: Map.get(scene, :outlines, []),
      volumes: Map.get(scene, :volumes, []),
      layers: Map.get(scene, :layers, []),
      projection: Map.get(look, :projection, :top),
      facing: Map.get(look, :facing, 0),
      facings: Map.get(look, :facings, 4),
      tilt: Map.get(look, :tilt, 1.0),
      heading: Heading.radians(Map.get(scene, :heading)) || Map.get(look, :heading, 0.0),
      pitch: Map.get(look, :pitch, 0.0),
      density: Map.get(look, :density),
      eye: eye_height(game, scene),
      picture: Map.get(scene, :picture),
      gpu: Map.get(scene, :gpu),
      gpu_size: Map.get(scene, :gpu_size)
    ]
  end

  @doc """
  How far above the ground the camera sits for a scene, in tiles, or `nil` to leave the
  projection its own: the scene's `:eye`, a height in tiles, or the art whose own
  `Cauldron2D.Atlas.eye_height/2` is used.
  """
  @spec eye_height(module(), map()) :: number() | nil
  def eye_height(game, scene) do
    case Map.get(scene, :eye) do
      nil -> nil
      tiles when is_number(tiles) -> tiles
      art -> Atlas.eye_height(Atlas.fetch(game.atlas()), art)
    end
  end

  @doc "The projections a view draws the atlas world in."
  @spec projections() :: [atom()]
  def projections, do: @projections

  @doc """
  The picture of `view` over a pane `{columns, rows}` tiles at zoom 1. Options: `:at`,
  the clock in milliseconds (default now); `:pane`, the pane's `{width, height}` in
  pixels, which a `:picture` with `native: :pane` is drawn at. Returns `nil` for a view
  with neither a focus and cell nor a picture.
  """
  @spec picture(t(), {pos_integer(), pos_integer()}, keyword()) :: Raster.t() | nil
  def picture(view, size, opts \\ [])

  def picture(%{projection: :picture, picture: nil}, _size, _opts), do: nil

  def picture(%{projection: :picture} = view, size, opts) do
    at = Keyword.get(opts, :at, now())

    view
    |> drawn(picture_size(view, size, Keyword.get(opts, :pane)), 1.0, :kitty, at)
    |> on_screen(view, at)
  end

  def picture(%{focus: nil}, _size, _opts), do: nil
  def picture(%{cell: nil}, _size, _opts), do: nil

  def picture(%{projection: :top} = view, {columns, rows}, opts) do
    at = Keyword.get(opts, :at, now())
    zoom = nearest(view.zoom, zoom_levels(view.atlas, :kitty))
    top_down(view, {columns, rows}, zoom, at)
  end

  def picture(view, {columns, rows}, opts) do
    at = Keyword.get(opts, :at, now())
    density = density(view, :kitty)

    view
    |> fitted(:kitty)
    |> drawn({columns * density, rows * density}, 1.0, :kitty, at)
    |> on_screen(view, at)
  end

  @doc """
  The world point under `{fx, fy}` — fractions of the width and height of the picture
  `picture/3` draws over `{columns, rows}` (`{0.0, 0.0}` its top-left corner) — on the
  ground; for a `:picture`, the fractions themselves; `nil` in first person, where a
  point of the picture is not a place.
  """
  @spec world_at(t(), {pos_integer(), pos_integer()}, {number(), number()}) ::
          {float(), float()} | nil
  def world_at(%{projection: :picture}, _size, fraction), do: fraction
  def world_at(%{projection: :first_person}, _size, _fraction), do: nil
  def world_at(%{focus: nil}, _size, _fraction), do: nil

  def world_at(%{projection: :top} = view, {columns, rows}, {fx, fy}) do
    zoom = nearest(view.zoom, zoom_levels(view.atlas, :kitty))
    {width, height} = Camera.zoomed({columns, rows}, zoom)
    {ox, oy} = Camera.exact_origin(view.focus, {width, height})
    {ox + fx * width, oy + fy * height}
  end

  def world_at(view, {columns, rows}, {fx, fy}) do
    density = density(view, :kitty)
    size = {columns * density, rows * density}
    fitted = fitted(view, :kitty)
    opts = projection_opts(fitted, size, 1.0, :kitty, now())
    at = {fx * columns * density, fy * rows * density}

    case view.projection do
      :iso -> Iso.unproject(view.atlas, at, opts)
      :oblique -> Oblique.unproject(view.atlas, at, opts)
      :mode7 -> Mode7.unproject(view.atlas, at, opts)
    end
  end

  @doc """
  The view's `:screen` and `:outlines` alone, on a transparent raster the size
  `picture/3` draws at over `{columns, rows}`, or `nil` when there are none; options as
  `picture/3`'s.
  """
  @spec screen_picture(t(), {pos_integer(), pos_integer()}, keyword()) :: Raster.t() | nil
  def screen_picture(view, pane, opts \\ []) do
    case screen_items(view) do
      [] ->
        nil

      items ->
        {width, height} = picture_dimensions(view, pane, Keyword.get(opts, :pane))
        Screen.compose(view.atlas, items, {width, height}, at: Keyword.get(opts, :at, now()))
    end
  end

  defp picture_dimensions(%{projection: :picture} = view, size, pane),
    do: picture_size(view, size, pane)

  defp picture_dimensions(%{projection: :top} = view, {columns, rows}, _pane) do
    tile = tile(view)

    case nearest(view.zoom, zoom_levels(view.atlas, :kitty)) do
      zoom when zoom >= 1 -> {round(columns * tile / zoom), round(rows * tile / zoom)}
      _out -> {columns * tile, rows * tile}
    end
  end

  defp picture_dimensions(view, {columns, rows}, _pane) do
    density = density(view, :kitty)
    {columns * density, rows * density}
  end

  defp picture_size(%{native: {width, height}}, _size, _pane), do: {width, height}
  defp picture_size(%{native: :pane}, _size, {width, height}), do: {width, height}

  defp picture_size(view, {columns, rows}, _pane) do
    density = density(view, :kitty)
    {columns * density, rows * density}
  end

  @doc """
  The top-down picture over `{columns, rows}` tiles at `zoom`, `:screen` and
  `:outlines` included: at a zoom in, `1 / zoom` of the tiles at the atlas's own
  pixels; at a zoom out, every tile drawn smaller by the whole number `1 / zoom`.
  """
  @spec top_down(t(), {number(), number()}, number(), integer()) :: Raster.t()
  def top_down(view, {columns, rows}, zoom, at) when zoom >= 1 do
    tile = tile(view)
    camera = camera(view, {columns, rows}, zoom)
    target = {round(columns * tile / zoom), round(rows * tile / zoom)}

    view
    |> world(camera, target, 1, at)
    |> on_screen(view, at)
  end

  def top_down(view, {columns, rows}, zoom, at) do
    tile = tile(view)

    view
    |> world(
      camera(view, {columns, rows}, zoom),
      {columns * tile, rows * tile},
      round(1 / zoom),
      at
    )
    |> on_screen(view, at)
  end

  @doc """
  The top-down world through `camera`, `target` `{width, height}` pixels, each tile
  `1 / scale` of the atlas's size: the grid, its movers, labels and volumes, between
  the layers behind and in front. No `:screen`.
  """
  @spec world(t(), Camera.t(), {pos_integer(), pos_integer()}, pos_integer(), integer()) ::
          Raster.t()
  def world(view, camera, target, scale, at) do
    {sx, sy} = scroll_pixels(camera, tile(view))
    behind = parallax(view, target, scale, false, at)
    front = parallax(view, target, scale, true, at)

    view.atlas
    |> Surface.compose(camera.cells, movers(view, camera),
      scale: scale,
      at: at,
      labels: labels(view, camera),
      volumes: volumes(view, camera),
      void: if(behind, do: :transparent, else: :opaque)
    )
    |> Raster.crop({div(sx, scale), div(sy, scale)}, target)
    |> under(behind)
    |> over(front)
  end

  @doc "The camera over `{columns, rows}` tiles at `zoom`, scrolled so the focus is at the exact centre."
  @spec camera(t(), {number(), number()}, number()) :: Camera.t()
  def camera(view, size, zoom),
    do:
      Camera.view(
        focus: view.focus,
        size: Camera.zoomed(size, zoom),
        cell: view.cell,
        scroll: true
      )

  @doc "How far a scrolled camera's cells are shifted, in pixels of a `tile`-pixel tile."
  @spec scroll_pixels(Camera.t(), pos_integer()) :: {integer(), integer()}
  def scroll_pixels(%Camera{scroll: {sx, sy}}, tile), do: {round(sx * tile), round(sy * tile)}

  @doc "The view's parallax layers behind (`front` false) or in front of the world, `target` pixels, or `nil` for none."
  @spec parallax(t(), {pos_integer(), pos_integer()}, pos_integer(), boolean(), integer()) ::
          Raster.t() | nil
  def parallax(%{layers: []}, _target, _scale, _front, _at), do: nil

  def parallax(view, {width, height}, scale, front, at) do
    tile = max(1, div(tile(view), scale))

    Parallax.compose(view.atlas, view.layers,
      focus: view.focus,
      size: {width / tile, height / tile},
      pixels: {width, height},
      at: at,
      scale: scale,
      front: front
    )
  end

  @doc "The view's movers in a camera's pixels, posed by heading, as `Cauldron2D.Surface.compose/4` takes them."
  @spec movers(t(), Camera.t()) :: list()
  def movers(%{movers: []}, _camera), do: []

  def movers(view, camera) do
    atlas = Atlas.fetch(view.atlas)
    tile = atlas.tile
    {ox, oy} = camera.origin

    Enum.map(view.movers, fn mover ->
      {art, {x, y}, heading} = with_heading(mover)
      {width, height} = Atlas.entry(atlas, art).size
      {pose, flip} = pose(heading)

      {art, {(x - ox) * tile + (tile - width) / 2, (y - oy) * tile + tile - height},
       tint_of(mover), pose, flip}
    end)
  end

  @doc "The view's labels in a camera's pixels."
  @spec labels(t(), Camera.t()) :: list()
  def labels(%{labels: []}, _camera), do: []

  def labels(view, camera) do
    tile = tile(view)
    {ox, oy} = camera.origin

    Enum.map(view.labels, fn
      {text, {x, y}, colour} -> {text, {(x - ox) * tile, (y - oy) * tile}, colour}
      {text, {x, y}, colour, opts} -> {text, {(x - ox) * tile, (y - oy) * tile}, colour, opts}
    end)
  end

  @doc "The view's volumes placed from a camera's origin, in tiles."
  @spec volumes(t(), Camera.t()) :: [map()]
  def volumes(%{volumes: []}, _camera), do: []

  def volumes(view, camera) do
    {ox, oy} = camera.origin

    Enum.map(view.volumes, fn volume ->
      volume = Map.new(volume)
      {x, y} = Map.fetch!(volume, :at)
      Map.put(volume, :at, {x - ox, y - oy})
    end)
  end

  @doc "`raster` with the view's `:screen` and `:outlines` drawn over it in its own pixels."
  @spec on_screen(Raster.t(), t(), integer()) :: Raster.t()
  def on_screen(raster, view, at) do
    case screen_items(view) do
      [] ->
        raster

      items ->
        Surface.stack(
          raster,
          Screen.compose(view.atlas, items, Raster.dimensions(raster), at: at)
        )
    end
  end

  @doc "The view's `:screen` items with its `:outlines` as `:box` items placed about the focus."
  @spec screen_items(t()) :: [Screen.item()]
  def screen_items(%{outlines: []} = view), do: view.screen
  def screen_items(%{focus: nil} = view), do: view.screen

  def screen_items(%{focus: {fx, fy}} = view) do
    tile = tile(view)

    view.screen ++
      for {{left, top, right, bottom}, colour} <- view.outlines do
        {:box, {(left - fx) * tile, (top - fy) * tile},
         {(right - left) * tile, (bottom - top) * tile}, colour,
         anchor: :centre, pivot: :top_left}
      end
  end

  @doc """
  The view's projection drawn into a picture `size` pixels, each `aspect` times as wide
  as tall, at the zoom `fitting_zoom/3` allows (magnified for a zoom in), `:screen`
  and `:outlines` over it.
  """
  @spec projected(t(), {pos_integer(), pos_integer()}, number(), atom(), integer()) ::
          Raster.t()
  def projected(%{projection: :picture} = view, size, aspect, mode, at),
    do: view |> drawn(size, aspect, mode, at) |> on_screen(view, at)

  def projected(view, {width, height}, aspect, mode, at) do
    zoom = fitting_zoom(view, height, mode)
    view = %{view | zoom: zoom}

    case zoom do
      zoom when zoom > 1 ->
        view
        |> drawn({ceil(width / zoom), ceil(height / zoom)}, aspect, mode, at)
        |> Surface.magnify(round(zoom))
        |> Raster.crop({0, 0}, {width, height})

      _native_or_out ->
        drawn(view, {width, height}, aspect, mode, at)
    end
    |> on_screen(view, at)
  end

  @doc "The view's projection, or its picture, drawn into `size` pixels, nothing over it."
  @spec drawn(t(), {pos_integer(), pos_integer()}, number(), atom(), integer()) :: Raster.t()
  def drawn(%{projection: :picture, picture: draw}, size, aspect, _mode, _at),
    do: draw.(size, aspect)

  def drawn(%{projection: :iso} = view, size, aspect, mode, at),
    do: Iso.compose(view.atlas, projection_opts(view, size, aspect, mode, at))

  def drawn(%{projection: :oblique} = view, size, aspect, mode, at),
    do: Oblique.compose(view.atlas, projection_opts(view, size, aspect, mode, at))

  def drawn(%{projection: :mode7} = view, size, aspect, mode, at),
    do: Mode7.render(view.atlas, projection_opts(view, size, aspect, mode, at))

  def drawn(%{projection: :first_person} = view, size, aspect, mode, at),
    do: FirstPerson.render(view.atlas, projection_opts(view, size, aspect, mode, at))

  @doc "The options the view's projection module is given for a picture `size` pixels."
  @spec projection_opts(t(), {pos_integer(), pos_integer()}, number(), atom(), integer()) ::
          keyword()
  def projection_opts(%{projection: :iso} = view, size, aspect, mode, at),
    do: [
      focus: view.focus,
      cell: view.cell,
      size: size,
      facing: view.facing,
      facings: facings(view, :iso),
      tilt: view.tilt * aspect,
      shrink: iso_shrink(projection_zoom(view, mode)),
      movers: posed_movers(view),
      labels: view.labels,
      volumes: view.volumes,
      at: at
    ]

  def projection_opts(%{projection: :oblique} = view, size, aspect, _mode, at),
    do: [
      focus: view.focus,
      cell: view.cell,
      size: size,
      squash: 0.5 * aspect,
      facing: view.facing,
      facings: facings(view, :oblique),
      movers: posed_movers(view),
      labels: view.labels,
      volumes: view.volumes,
      at: at
    ]

  def projection_opts(%{projection: projection} = view, size, aspect, _mode, at)
      when projection in [:mode7, :first_person],
      do:
        [
          position: view.focus,
          heading: view.heading,
          pitch: view.pitch,
          cell: view.cell,
          size: size,
          aspect: aspect,
          movers: posed_movers(view),
          volumes: view.volumes,
          at: at
        ] ++ if(view.eye, do: [eye: view.eye], else: [])

  @doc """
  How many pixels a tile is drawn with in a projected picture: in a mode whose picture
  is scaled to its pane (`:kitty`, `:iterm2`), the view's `:density` (a number, or a
  map by projection), else half the atlas's tile, and `4` in first person, mode 7 and a
  picture, divided by the zoom; in any other mode the atlas's tile.
  """
  @spec density(t(), atom()) :: pos_integer()
  def density(view, mode) when mode in @fitted do
    zoom = projection_zoom(view, mode)
    asked = if shrinks?(view.projection), do: max(zoom, 1), else: zoom
    max(1, round(native_density(view) / asked))
  end

  def density(view, _mode), do: tile(view)

  @doc """
  The view as a picture scaled to its pane draws it: at a zoom in, a smaller picture;
  at a zoom out, the isometric view draws more world into the same picture and the
  others stay at zoom 1.
  """
  @spec fitted(t(), atom()) :: t()
  def fitted(view, mode) do
    zoom = projection_zoom(view, mode)
    %{view | zoom: if(shrinks?(view.projection), do: min(zoom, 1), else: 1)}
  end

  @doc """
  The zoom a projection is drawn at in a picture `height` pixels tall: the zoom asked for,
  rounded to a level of `zoom_levels/3`, pulled back until the tallest art stands in the
  half of the picture above its feet with a tile to spare.
  """
  @spec fitting_zoom(t(), pos_integer(), atom()) :: number()
  def fitting_zoom(view, height, mode) do
    levels = zoom_levels(view.atlas, mode, view.projection)
    wanted = nearest(view.zoom, levels)
    room = 2 * (Atlas.tallest(view.atlas) + Atlas.fetch(view.atlas).tile)

    levels
    |> Enum.filter(&(&1 <= wanted))
    |> Enum.find(List.last(levels), &(height / &1 >= room))
  end

  @doc "The zoom the view's projection is drawn at in `mode`: its zoom, rounded to a level."
  @spec projection_zoom(t(), atom()) :: number()
  def projection_zoom(view, mode),
    do: nearest(view.zoom, zoom_levels(view.atlas, mode, view.projection))

  @doc "The zoom levels drawn exactly in `mode` for the top-down view, largest first."
  @spec zoom_levels(Atlas.name(), atom() | nil) :: [number()]
  def zoom_levels(atlas, mode), do: zoom_levels(atlas, mode, :top)

  @doc """
  The zoom levels drawn exactly in `mode` for `projection`, largest first: top-down, 4
  down to a sixteenth, kept to the divisors of the atlas's tile zoomed out (in
  `:braille`, those where a tile is a whole number of dots); isometric 2 down to a
  quarter; oblique 2 down to a half; first person, mode 7 and a picture `1` alone.
  """
  @spec zoom_levels(Atlas.name(), atom() | nil, atom()) :: [number()]
  def zoom_levels(_atlas, _mode, :picture), do: [1]
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

  @doc "The level of `levels` nearest `zoom`, by ratio."
  @spec nearest(number(), [number()]) :: number()
  def nearest(zoom, levels), do: Enum.min_by(levels, &abs(:math.log(&1 / zoom)))

  @doc "The view's movers as the projections take them, `{art, position}` or `{art, position, heading}`."
  @spec posed_movers(t()) :: list()
  def posed_movers(view) do
    Enum.map(view.movers, fn
      {art, position, heading, _opts} -> {art, position, heading}
      mover -> mover
    end)
  end

  @doc "The view's movers as `{art, position, tint}`."
  @spec tinted_movers(t()) :: list()
  def tinted_movers(view),
    do: Enum.map(view.movers, fn mover -> {elem(mover, 0), elem(mover, 1), tint_of(mover)} end)

  @doc "The view's movers as `{art, position}`."
  @spec flat_movers(t()) :: list()
  def flat_movers(view),
    do: Enum.map(view.movers, fn mover -> {elem(mover, 0), elem(mover, 1)} end)

  @doc "The pose and mirroring an art is drawn with for a heading in radians: `{pose, flip?}`."
  @spec pose(number() | nil) :: {:front | :back | :side | nil, boolean()}
  def pose(nil), do: {nil, false}

  def pose(heading) do
    {across, down} = {:math.cos(heading), :math.sin(heading)}

    cond do
      down > 0.5 -> {:front, false}
      down < -0.5 -> {:back, false}
      true -> {:side, across < 0}
    end
  end

  @doc "How many facings make a full turn in `projection` for the view."
  @spec facings(t(), atom()) :: number()
  def facings(%{facings: facings}, projection) when is_map(facings),
    do: Map.get(facings, projection, default_facings(projection))

  def facings(_view, :oblique), do: default_facings(:oblique)
  def facings(%{facings: facings}, _projection), do: facings

  @doc "How many times smaller the isometric view draws its own world at `zoom`."
  @spec iso_shrink(number()) :: pos_integer()
  def iso_shrink(zoom) when zoom >= 1, do: 1
  def iso_shrink(zoom), do: min(4, max(1, round(1 / zoom)))

  @doc "Whether `projection` draws its own world smaller to zoom out."
  @spec shrinks?(atom()) :: boolean()
  def shrinks?(projection), do: projection == :iso

  @doc "The view's own density for its projection, before the zoom divides it."
  @spec native_density(t()) :: number()
  def native_density(%{projection: projection} = view),
    do: asked_density(view.density, projection) || default_density(view, projection)

  defp asked_density(nil, _projection), do: nil
  defp asked_density(density, projection) when is_map(density), do: Map.get(density, projection)
  defp asked_density(density, _projection), do: density

  defp default_density(_view, projection) when projection in @sampled, do: @sampled_density
  defp default_density(view, _projection), do: tile(view) / 2

  defp default_facings(:oblique), do: 1
  defp default_facings(_projection), do: 4

  defp with_heading({art, position}), do: {art, position, nil}
  defp with_heading({art, position, heading}), do: {art, position, heading}
  defp with_heading({art, position, heading, _opts}), do: {art, position, heading}

  defp tint_of({_art, _position, _heading, opts}), do: Map.get(opts, :tint)
  defp tint_of(_mover), do: nil

  defp under(raster, nil), do: raster
  defp under(raster, behind), do: Surface.stack(behind, raster)

  defp over(raster, nil), do: raster
  defp over(raster, front), do: Surface.stack(raster, front)

  defp tile(view), do: Atlas.fetch(view.atlas).tile

  defp whole(number) when is_float(number) and number == trunc(number), do: trunc(number)
  defp whole(number), do: number

  defp now, do: System.monotonic_time(:millisecond)

  defp in_radians(view),
    do: %{view | movers: Heading.movers(view.movers), heading: Heading.radians(view.heading)}

  defp picture_projection(%{picture: nil} = view), do: view
  defp picture_projection(%{picture: false} = view), do: view
  defp picture_projection(view), do: %{view | projection: :picture}
end
