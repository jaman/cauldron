defmodule Cauldron2D.Parallax do
  @moduledoc """
  A background of several depths, each read at its own share of the camera's motion.

      layers = [
        Cauldron2D.Parallax.layer(name: :sky, cell: sky, factor: 0.0, void: :opaque),
        Cauldron2D.Parallax.layer(name: :hills, cell: hills, factor: {0.2, 0.05}),
        Cauldron2D.Parallax.layer(name: :trees, cell: trees, factor: {0.6, 0.2}),
        Cauldron2D.Parallax.layer(name: :grass, cell: grass, factor: {1.4, 1.0}, front: true)
      ]

      behind = Cauldron2D.Parallax.compose(:atlas, layers, focus: focus, size: {40, 24}, at: now)
      Cauldron2D.Surface.compose(:atlas, cells, movers, under: behind, void: :transparent)

  `compose/3` draws the layers of one side into one raster the size of the pane, back to
  front in list order: the layers behind the world by default, those with `front: true`
  when given `front: true`. The backmost layer wants `void: :opaque` so the picture has a
  background; every other layer wants `:transparent`.

  A layer's picture is kept while the camera stays within one of that layer's tiles. A
  layer whose movers move must be built with `cache: false`.

  A layer's movers are `Cauldron2D.Surface` movers in the layer's own tiles —
  `{art, {x, y}}` or `{art, {x, y}, tint}`.
  """

  alias Cauldron2D.{Atlas, Camera, Render, Surface}
  alias Cauldron2D.Atlas.Tables
  alias Cauldron2D.Parallax.{Bands, Layer, Panorama, Scatter, Strip}
  alias FrenchCurve.Raster

  @table :cauldron_parallax

  @doc "A layer, as `Cauldron2D.Parallax.Layer.new/1` builds it."
  @spec layer(keyword()) :: Layer.t()
  defdelegate layer(opts), to: Layer, as: :new

  @doc "A layer that is one picture repeated, as `Panorama.layer/1` builds it."
  @spec panorama(keyword()) :: Layer.t()
  defdelegate panorama(opts), to: Panorama, as: :layer

  @doc "A cell function placing art by hashing the coordinate, as `Scatter.cells/1` builds it."
  @spec scatter(keyword()) :: ({integer(), integer()} -> term())
  defdelegate scatter(opts), to: Scatter, as: :cells

  @doc "A cell function over authored tiles, as `Strip.cells/2` builds it."
  @spec strip([[term()]], keyword()) :: ({integer(), integer()} -> term())
  def strip(rows, opts \\ []), do: Strip.cells(rows, opts)

  @doc "Rows of cells from rows of characters, as `Strip.legend/2` builds them."
  @spec legend([String.t()], map()) :: [[term()]]
  defdelegate legend(lines, legend), to: Strip

  @doc "Bands of rows with their own factors, as `Bands.new/1` builds them."
  @spec bands([{Range.t(), number()}]) :: Bands.t()
  defdelegate bands(ranges), to: Bands, as: :new

  @doc """
  The camera for one layer: its own origin, its own cells and its own sub-tile scroll.

  ## Options

    * `:focus` — the world point the camera is on, required
    * `:size` — `{columns, rows}` of the pane in tiles, required
    * `:at` — the time in milliseconds. Default `0`
  """
  @spec view(Layer.t(), keyword()) :: Camera.t()
  def view(%Layer{} = layer, opts) do
    Camera.view(
      focus: Layer.focus(layer, Keyword.fetch!(opts, :focus), Keyword.get(opts, :at, 0)),
      size: Keyword.fetch!(opts, :size),
      cell: layer.cell,
      scroll: true
    )
  end

  @doc """
  The layers of one side composed into one raster, or `nil` where that side has none.

  ## Options

    * `:focus` — the world point the camera is on, required
    * `:size` — `{columns, rows}` of the pane in whole tiles, required
    * `:at` — the time in milliseconds, for animation and drift. Default `0`
    * `:scale` — a positive integer dividing the tile size, as
      `Cauldron2D.Surface.compose/4` takes. Default `1`
    * `:pixels` — the result's exact size in pixels, for a caller that has one already and
      needs the picture to match it. Default `:size` times the tile
    * `:front` — `true` for the layers over the world, `false` for those behind it.
      Default `false`
  """
  @spec compose(Atlas.name() | Atlas.t(), [Layer.t()], keyword()) :: Raster.t() | nil
  def compose(atlas, layers, opts) do
    front = Keyword.get(opts, :front, false)

    case Enum.filter(layers, &(&1.front == front)) do
      [] -> nil
      chosen -> draw(Atlas.fetch(atlas), chosen, opts)
    end
  end

  @doc "Forget every kept layer picture of `atlas`."
  @spec forget(Atlas.name()) :: :ok
  def forget(atlas) when is_atom(atlas) do
    @table |> Tables.ensure() |> :ets.match_delete({{atlas, :_, :_, :_, :_}, :_})
    :ok
  end

  defp draw(atlas, layers, opts) do
    focus = Keyword.fetch!(opts, :focus)
    {columns, rows} = Keyword.fetch!(opts, :size)
    at = Keyword.get(opts, :at, 0)
    scale = Keyword.get(opts, :scale, 1)
    tile = max(1, div(atlas.tile, scale))

    target =
      Keyword.get_lazy(opts, :pixels, fn ->
        {round(columns * tile), round(rows * tile)}
      end)

    [backmost | rest] =
      Enum.map(layers, &picture(atlas, &1, focus, {columns, rows}, at, scale, tile, target))

    case rest do
      [] ->
        backmost

      _ ->
        Render.render(target, Enum.map(rest, &{:raster, &1, {0, 0}}), background: backmost)
    end
  end

  defp picture(atlas, layer, focus, size, at, scale, tile, target) do
    layer_focus = Layer.focus(layer, focus, at)
    {ex, ey} = Camera.exact_origin(layer_focus, size)
    origin = {floor(ex), floor(ey)}
    scroll = {floor((ex - floor(ex)) * tile), floor((ey - floor(ey)) * tile)}

    atlas
    |> kept(layer, origin, layer_focus, size, at, scale)
    |> Raster.crop(scroll, target)
    |> Bands.roll(layer.bands, layer_focus, tile)
  end

  defp kept(atlas, %Layer{cache: false} = layer, origin, focus, size, at, scale),
    do: build(atlas, layer, origin, focus, size, at, scale)

  defp kept(atlas, layer, origin, focus, size, at, scale) do
    table = Tables.ensure(@table)
    key = {atlas.name, layer.name, origin, scale, frame(layer, at)}

    case :ets.lookup(table, key) do
      [{^key, raster}] ->
        raster

      [] ->
        raster = build(atlas, layer, origin, focus, size, at, scale)
        :ets.match_delete(table, {{atlas.name, layer.name, :_, scale, :_}, :_})
        :ets.insert(table, {key, raster})
        raster
    end
  end

  defp build(atlas, %Layer{picture: picture} = layer, origin, _focus, size, at, scale)
       when is_map(picture) do
    tile = max(1, div(atlas.tile, scale))
    {columns, rows} = size

    Panorama.render(
      atlas,
      picture,
      origin,
      {(ceil(columns) + 1) * tile, (ceil(rows) + 1) * tile},
      tile,
      scale,
      at,
      layer.void
    )
  end

  defp build(atlas, layer, origin, focus, size, at, scale) do
    camera = Camera.view(focus: focus, size: size, cell: layer.cell, scroll: true)
    rect = {origin, {camera.columns, camera.rows}}

    Surface.compose(atlas, camera.cells, placed(layer, rect, origin, atlas.tile),
      scale: scale,
      at: at,
      void: layer.void,
      volumes: shifted(Layer.volumes(layer, rect), camera.origin)
    )
  end

  defp placed(layer, rect, {ox, oy}, tile) do
    layer
    |> Layer.movers(rect)
    |> Enum.map(fn
      {art, {x, y}} -> {art, {(x - ox) * tile, (y - oy) * tile}}
      {art, {x, y}, tint} -> {art, {(x - ox) * tile, (y - oy) * tile}, tint}
    end)
  end

  defp shifted(volumes, {ox, oy}) do
    Enum.map(volumes, fn volume ->
      Map.update!(volume, :at, fn
        {x, y} -> {x - ox, y - oy}
        {x, y, z} -> {x - ox, y - oy, z}
      end)
    end)
  end

  defp frame(%Layer{animated: false}, _at), do: 0
  defp frame(%Layer{fps: fps}, at), do: div(round(at) * fps, 1000)
end
