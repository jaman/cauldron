defmodule Cauldron2D.Net.Scene do
  @moduledoc """
  A scene as data a client draws itself: every function of the game's already
  evaluated — the cells of the world and of each parallax layer over the part of them the
  pane shows, a layer's movers and volumes — so the client does only the drawing that
  `Cauldron2D.Draw` does, and the cells it has been sent before are not sent again.

      {writer, payload} = Cauldron2D.Net.Scene.write(Cauldron2D.Net.Scene.writer(), view, {40, 22})
      {reader, view} = Cauldron2D.Net.Scene.read(Cauldron2D.Net.Scene.reader(atlas), payload)

  `write/4` keeps, per client, the cells and cell kinds it has sent; `read/2` keeps the
  same on the other side, and answers a `Cauldron2D.Draw` view that draws as the one
  written did (`Cauldron2D.Draw.picture/3`).

  ## The payload

    * `projection`, `zoom`, `facing`, `facings`, `tilt`, `heading`, `pitch`, `eye`,
      `density` — the view's, as `Cauldron2D.Draw` holds them (`facings` and `density`
      may be maps by projection; `null` where unset)
    * `focus` — `[x, y]`
    * `kinds` — the cell kinds not sent before, `[[k, base, [overlay, ...], tint], ...]`:
      a kind is a cell's arts and tint, named as `Cauldron2D.Net.Scene.Items` names them,
      and `k` a number from 1 the client keeps it under
    * `cells` — `%{"world" => changes, "<layer>" => changes}`, each change flat
      `[x, y, k, x, y, k, ...]` in that grid's own tiles, `k` `0` for an empty tile;
      a tile not sent is empty
    * `movers`, `labels`, `volumes`, `outlines` — as `Cauldron2D.Net.Scene.Items` writes them
    * `screen` — the `:screen` items, when the writer is asked for them (`screen: true`)
    * `layers` — each `%{name, front, void, focus, animated, fps, movers, volumes,
      picture, bands}`: `focus` the point the layer is seen from now, `[x, y]`;
      `picture` a panorama's `%{art, size, wrap, at, cover}`, else `null`; `bands`
      `[[first_row, last_row, factor], ...]`, else `null`
    * `tints` — `[[art, tint], ...]` the arts the scene draws tinted, for a client that
      asks for tinted frames
    * `tinted_cells` — `[[base, [overlay, ...], tint], ...]` the tinted kinds with
      overlays the tile's size, each with only those overlays, for a client that asks
      for the cells blended and tinted (`Cauldron2D.Net.Atlas.tinted_cell/4`)
  """

  alias Cauldron2D.{Atlas, Camera, Draw}
  alias Cauldron2D.Net.Scene.Items
  alias Cauldron2D.Parallax.{Bands, Layer}
  alias Cauldron2D.Projection.{Iso, Oblique}

  @range 25

  defmodule Writer do
    @moduledoc "What a client has been sent: the cells of each grid and the cell kinds."

    @type t :: %__MODULE__{sent: map(), kinds: map(), next: pos_integer()}

    defstruct sent: %{}, kinds: %{}, next: 1
  end

  defmodule Reader do
    @moduledoc "What a client has received: the cells of each grid, the cell kinds and the atlas's arts by name."

    @type t :: %__MODULE__{atlas: Atlas.name() | nil, cells: map(), kinds: map(), arts: map()}

    defstruct [:atlas, cells: %{}, kinds: %{}, arts: %{}]
  end

  @doc "A writer that has sent nothing."
  @spec writer() :: Writer.t()
  def writer, do: %Writer{}

  @doc "A reader for `atlas` (a name or the struct) that has received nothing."
  @spec reader(Atlas.name() | Atlas.t()) :: Reader.t()
  def reader(atlas) do
    atlas = Atlas.fetch(atlas)
    %Reader{atlas: atlas.name, arts: Items.arts(atlas)}
  end

  @doc """
  Whether a client can draw `view` from data: neither a `:picture` (drawn by the
  game's function) nor a volume whose shape is a module of the game's own.
  """
  @spec drawable?(Draw.t()) :: boolean()
  def drawable?(%Draw{projection: :picture}), do: false
  def drawable?(%Draw{focus: nil}), do: false
  def drawable?(%Draw{volumes: volumes}), do: Enum.all?(volumes, &Items.portable?/1)

  @doc """
  The payload for `view` over a pane `{columns, rows}` tiles at zoom 1, and the writer
  holding what it sent. Options: `:screen`, whether the `:screen` and `:outlines` go
  too (default `true`); `:at`, the clock in milliseconds (default now).
  """
  @spec write(Writer.t(), Draw.t(), {pos_integer(), pos_integer()}, keyword()) ::
          {Writer.t(), map()}
  def write(writer, %Draw{} = view, pane, opts \\ []) do
    at = Keyword.get(opts, :at, System.monotonic_time(:millisecond))
    screen? = Keyword.get(opts, :screen, true)

    size =
      Camera.zoomed(pane, Draw.nearest(view.zoom, Draw.zoom_levels(view.atlas, :kitty, :top)))

    {writer, world} = grid(writer, "world", view.cell, region(view, pane))

    {writer, layers, layer_cells} =
      Enum.reduce(view.layers, {writer, [], %{}}, fn layer, {writer, layers, cells} ->
        {writer, written, changes} = layer(writer, layer, view.focus, size, at)
        {writer, [written | layers], Map.put(cells, Atom.to_string(layer.name), changes)}
      end)

    {writer, kinds} = new_kinds(writer)

    payload = %{
      projection: Atom.to_string(view.projection),
      zoom: view.zoom,
      facing: view.facing,
      facings: by_projection(view.facings),
      tilt: view.tilt,
      heading: view.heading,
      pitch: view.pitch,
      eye: view.eye,
      density: by_projection(view.density),
      focus: Tuple.to_list(view.focus),
      kinds: kinds,
      cells: Map.put(layer_cells, "world", world),
      movers: Enum.map(view.movers, &Items.mover/1),
      labels: Enum.map(view.labels, &Items.label/1),
      volumes: Enum.map(view.volumes, &Items.volume/1),
      layers: Enum.reverse(layers),
      screen: if(screen?, do: Enum.map(view.screen, &Items.screen_item/1), else: []),
      outlines: if(screen?, do: Enum.map(view.outlines, &Items.outline/1), else: []),
      tints: tinted(view, writer),
      tinted_cells: tinted_cells(view, writer)
    }

    {writer, payload}
  end

  @doc "The reader holding `payload`'s cells, and the `Cauldron2D.Draw` view it describes."
  @spec read(Reader.t(), map()) :: {Reader.t(), Draw.t()}
  def read(%Reader{} = reader, payload) do
    reader = Enum.reduce(fetch(payload, :kinds), reader, &kind_read/2)

    reader =
      Enum.reduce(fetch(payload, :cells), reader, fn {grid, changes}, reader ->
        %{
          reader
          | cells:
              Map.update(
                reader.cells,
                grid,
                apply_changes(%{}, changes),
                &apply_changes(&1, changes)
              )
        }
      end)

    arts = reader.arts

    view =
      Draw.new(
        atlas: reader.atlas,
        projection: String.to_existing_atom(fetch(payload, :projection)),
        zoom: fetch(payload, :zoom),
        facing: fetch(payload, :facing),
        facings: read_by_projection(fetch(payload, :facings)),
        tilt: fetch(payload, :tilt),
        heading: fetch(payload, :heading),
        pitch: fetch(payload, :pitch),
        eye: fetch(payload, :eye),
        density: read_by_projection(fetch(payload, :density)),
        focus: List.to_tuple(fetch(payload, :focus)),
        cell: cell_fn(reader, "world"),
        movers: Enum.map(fetch(payload, :movers), &Items.read_mover(&1, arts)),
        labels: Enum.map(fetch(payload, :labels), &Items.read_label/1),
        volumes: Enum.map(fetch(payload, :volumes), &Items.read_volume/1),
        layers: Enum.map(fetch(payload, :layers), &read_layer(&1, reader)),
        screen: Enum.map(fetch(payload, :screen), &Items.read_screen_item(&1, arts)),
        outlines: Enum.map(fetch(payload, :outlines), &Items.read_outline/1)
      )

    {reader, view}
  end

  defp region(%Draw{projection: :top} = view, pane) do
    camera =
      Draw.camera(view, pane, Draw.nearest(view.zoom, Draw.zoom_levels(view.atlas, :kitty)))

    {camera.origin, {length(hd(camera.cells)), length(camera.cells)}}
  end

  defp region(%Draw{projection: projection} = view, {columns, rows})
       when projection in [:iso, :oblique] do
    density = Draw.density(view, :kitty)
    fitted = Draw.fitted(view, :kitty)
    opts = Draw.projection_opts(fitted, {columns * density, rows * density}, 1.0, :kitty, 0)
    module = if projection == :iso, do: Iso, else: Oblique

    case module.cells(view.atlas, opts) do
      [] ->
        {{0, 0}, {0, 0}}

      cells ->
        {xs, ys} = cells |> Enum.map(&elem(&1, 0)) |> Enum.unzip()

        {{Enum.min(xs) - 1, Enum.min(ys) - 1},
         {Enum.max(xs) - Enum.min(xs) + 3, Enum.max(ys) - Enum.min(ys) + 3}}
    end
  end

  defp region(%Draw{focus: {fx, fy}}, _pane),
    do: {{floor(fx) - @range, floor(fy) - @range}, {2 * @range + 1, 2 * @range + 1}}

  defp grid(writer, name, cell, {{ox, oy}, {width, height}}) do
    sent = Map.get(writer.sent, name, %{})

    {writer, sent, changes} =
      for y <- oy..(oy + height - 1)//1,
          x <- ox..(ox + width - 1)//1,
          reduce: {writer, sent, []} do
        {writer, sent, changes} ->
          {writer, k} = kind_of(writer, cell.({x, y}))

          if Map.get(sent, {x, y}, 0) == k,
            do: {writer, sent, changes},
            else: {writer, Map.put(sent, {x, y}, k), [k, y, x | changes]}
      end

    {%{writer | sent: Map.put(writer.sent, name, sent)}, Enum.reverse(changes)}
  end

  defp kind_of(writer, :void), do: {writer, 0}

  defp kind_of(writer, cell) do
    case Map.fetch(writer.kinds, cell) do
      {:ok, {k, _sent?}} ->
        {writer, k}

      :error ->
        {%{
           writer
           | kinds: Map.put(writer.kinds, cell, {writer.next, false}),
             next: writer.next + 1
         }, writer.next}
    end
  end

  defp new_kinds(writer) do
    fresh = for {cell, {k, false}} <- writer.kinds, do: {cell, k}

    kinds =
      for {{base, overlays, tint}, k} <- Enum.sort_by(fresh, &elem(&1, 1)),
          do: [
            k,
            Items.art_name(base),
            Enum.map(overlays, &Items.art_name/1),
            Items.tint_name(tint)
          ]

    sent =
      Enum.reduce(fresh, writer.kinds, fn {cell, k}, acc -> Map.put(acc, cell, {k, true}) end)

    {%{writer | kinds: sent}, kinds}
  end

  defp layer(writer, %Layer{} = layer, focus, size, at) do
    layer_focus = Layer.focus(layer, focus, at)
    camera = Camera.view(focus: layer_focus, size: size, cell: fn _ -> :void end, scroll: true)
    rect = {camera.origin, {camera.columns, camera.rows}}

    {writer, changes} =
      if layer.picture,
        do: {writer, []},
        else: grid(writer, Atom.to_string(layer.name), layer.cell, rect)

    written = %{
      name: Atom.to_string(layer.name),
      front: layer.front,
      void: Atom.to_string(layer.void),
      focus: Tuple.to_list(layer_focus),
      animated: layer.animated,
      fps: layer.fps,
      movers: Enum.map(Layer.movers(layer, rect), &layer_mover/1),
      volumes: Enum.map(Layer.volumes(layer, rect), &Items.volume/1),
      picture: picture(layer.picture),
      bands: bands(layer.bands)
    }

    {writer, written, changes}
  end

  defp layer_mover({art, {x, y}}), do: [Items.art_name(art), x / 1, y / 1, nil, nil]

  defp layer_mover({art, {x, y}, tint}),
    do: [Items.art_name(art), x / 1, y / 1, nil, Items.tint_name(tint)]

  defp picture(nil), do: nil

  defp picture(picture),
    do: %{
      art: Items.art_name(picture.art),
      size: Tuple.to_list(picture.size),
      wrap: Atom.to_string(picture.wrap),
      at: Tuple.to_list(picture.at),
      cover: picture.cover
    }

  defp bands(nil), do: nil

  defp bands(%Bands{ranges: ranges}),
    do: for({first..last//_, factor} <- ranges, do: [first, last, factor])

  defp tinted(view, writer) do
    from_cells =
      for {{base, overlays, tint}, _} <- writer.kinds,
          tint != nil,
          art <- [base | overlays],
          do: [Items.art_name(art), Atom.to_string(tint)]

    from_movers =
      for {art, _at, _heading, %{tint: tint}} <- view.movers,
          tint != nil,
          do: [Items.art_name(art), Atom.to_string(tint)]

    Enum.uniq(from_cells ++ from_movers)
  end

  defp tinted_cells(view, writer) do
    atlas = Atlas.fetch(view.atlas)
    tile = {atlas.tile, atlas.tile}

    for {{base, overlays, tint}, _} <- writer.kinds,
        tint != nil,
        fitting = Enum.filter(overlays, &(Atlas.entry(atlas, &1).size == tile)),
        fitting != [],
        uniq: true,
        do: [
          Items.art_name(base),
          Enum.map(fitting, &Items.art_name/1),
          Atom.to_string(tint)
        ]
  end

  defp by_projection(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {Atom.to_string(k), v} end)

  defp by_projection(value), do: value

  defp read_by_projection(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {String.to_existing_atom(k), v} end)

  defp read_by_projection(value), do: value

  defp kind_read([k, base, overlays, tint], reader) do
    arts = reader.arts

    cell =
      {Map.fetch!(arts, base), Enum.map(overlays, &Map.fetch!(arts, &1)), Items.read_tint(tint)}

    %{reader | kinds: Map.put(reader.kinds, k, cell)}
  end

  defp apply_changes(cells, [x, y, k | rest]), do: apply_changes(Map.put(cells, {x, y}, k), rest)
  defp apply_changes(cells, []), do: cells

  defp cell_fn(reader, grid) do
    cells = Map.get(reader.cells, grid, %{})
    kinds = reader.kinds

    fn position ->
      case Map.get(cells, position, 0) do
        0 -> :void
        k -> Map.fetch!(kinds, k)
      end
    end
  end

  defp read_layer(layer, reader) do
    arts = reader.arts
    name = fetch(layer, :name)
    picture = fetch(layer, :picture)

    Layer.new(
      name: String.to_existing_atom(name),
      cell: cell_fn(reader, name),
      movers: Enum.map(fetch(layer, :movers), &read_layer_mover(&1, arts)),
      volumes: Enum.map(fetch(layer, :volumes), &Items.read_volume/1),
      factor: {0.0, 0.0},
      drift: {0.0, 0.0},
      origin: List.to_tuple(fetch(layer, :focus)),
      void: String.to_existing_atom(fetch(layer, :void)),
      front: fetch(layer, :front),
      animated: fetch(layer, :animated),
      fps: fetch(layer, :fps),
      cache: false,
      picture: picture && read_picture(picture, arts),
      bands: read_bands(fetch(layer, :bands))
    )
  end

  defp read_layer_mover([art, x, y, _heading, nil], arts), do: {Map.fetch!(arts, art), {x, y}}

  defp read_layer_mover([art, x, y, _heading, tint], arts),
    do: {Map.fetch!(arts, art), {x, y}, Items.read_tint(tint)}

  defp read_picture(picture, arts),
    do: %{
      art: Map.fetch!(arts, fetch(picture, :art)),
      size: List.to_tuple(fetch(picture, :size)),
      wrap: String.to_existing_atom(fetch(picture, :wrap)),
      at: List.to_tuple(fetch(picture, :at)),
      cover: fetch(picture, :cover)
    }

  defp read_bands(nil), do: nil

  defp read_bands(ranges),
    do: Bands.new(for [first, last, factor] <- ranges, do: {first..last, factor})

  defp fetch(map, key), do: Map.get_lazy(map, key, fn -> Map.fetch!(map, Atom.to_string(key)) end)
end
