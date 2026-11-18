defmodule Cauldron2D.Net.Drawn do
  @moduledoc """
  A scene turned into what goes to one client, as the drawing setting
  (`Cauldron2D.Net.Drawing`) has it, over the client's pane; what a world's session and
  a front's session both send.

      drawn = Cauldron2D.Net.Drawn.new(Cauldron2D.Net.Drawing.resolve(), :png)
      drawn = Cauldron2D.Net.Drawn.pane(drawn, {40, 22})
      {drawn, pushes} = Cauldron2D.Net.Drawn.pushes(drawn, view)

  `view` is a `Cauldron2D.Draw` view. The pushes, by who draws the world and the screen:

    * both the server — `{"picture", picture}`: PNG bytes, or the `Cauldron2D.Raster`
      itself for a client in this node (`:raster`)
    * both the client — `{"scene", payload}`, `Cauldron2D.Net.Scene`'s, after a
      `{"tinted", %{art, tint, index, png}}` for each art the scene first draws through
      a tint (`Cauldron2D.Net.Atlas.tinted/3`, the PNG in base64), and a
      `{"tinted_cell", %{base, overlays, tint, index, png}}` for each tinted cell kind
      with overlays the tile's size it first draws (`Cauldron2D.Net.Atlas.tinted_cell/4`)
    * the world the client, the screen the server — `{"scene", payload}` without the
      screen, and `{"overlay", picture}` whenever the screen changes: the `:screen` and
      `:outlines` on a transparent picture the size the world is drawn at, `""` (or
      `nil` as a raster) when there are none
    * the world the server, the screen the client — `{"picture", picture}` without the
      screen, and `{"scene", payload}` carrying only the screen (no cells, layers or
      movers)

  A scene a client cannot draw from data (`Cauldron2D.Net.Scene.drawable?/1`) goes as a
  picture whatever the setting. Nothing is pushed before the client gives its pane.
  """

  alias Cauldron2D.{Atlas, Draw}
  alias Cauldron2D.Net.Atlas, as: NetAtlas
  alias Cauldron2D.Net.{Drawing, Picture, Scene}

  @type t :: %__MODULE__{
          drawing: Drawing.t(),
          picture: :png | :raster,
          pane: {pos_integer(), pos_integer()} | nil,
          writer: term(),
          overlay: term(),
          tinted: MapSet.t()
        }

  defstruct [
    :drawing,
    :writer,
    picture: :png,
    pane: nil,
    overlay: :none,
    tinted: MapSet.new()
  ]

  @doc "Nothing drawn yet, for `drawing`, with pictures pushed as `picture`."
  @spec new(Drawing.t(), :png | :raster) :: t()
  def new(drawing, picture),
    do: %__MODULE__{drawing: drawing, picture: picture, writer: Scene.writer()}

  @doc "The client's pane: the tiles across and down it shows at zoom 1."
  @spec pane(t(), {pos_integer(), pos_integer()}) :: t()
  def pane(drawn, pane), do: %{drawn | pane: pane, overlay: :none}

  @doc "Whether the client has given its pane."
  @spec paned?(t()) :: boolean()
  def paned?(drawn), do: drawn.pane != nil

  @doc "The pushes that show `view`."
  @spec pushes(t(), Draw.t()) :: {t(), [{String.t(), term()}]}
  def pushes(%{pane: nil} = drawn, _view), do: {drawn, []}

  def pushes(drawn, view) do
    if Scene.drawable?(view),
      do: by_parts(drawn, view, drawn.drawing),
      else: whole(drawn, view)
  end

  @doc "The world point under `{fx, fy}`, fractions of the picture of `view` over the pane."
  @spec world_at(t(), Draw.t(), {number(), number()}) :: {float(), float()} | nil
  def world_at(%{pane: nil}, _view, _fraction), do: nil
  def world_at(drawn, view, fraction), do: Draw.world_at(view, drawn.pane, fraction)

  defp by_parts(drawn, view, %{world: :server, screen: :server}), do: whole(drawn, view)

  defp by_parts(drawn, view, %{world: :client, screen: :client}) do
    {writer, payload} = Scene.write(drawn.writer, view, drawn.pane)
    {drawn, tinted} = tinted(%{drawn | writer: writer}, view, payload)
    {drawn, tinted ++ [{"scene", payload}]}
  end

  defp by_parts(drawn, view, %{world: :client, screen: :server}) do
    {writer, payload} = Scene.write(drawn.writer, view, drawn.pane, screen: false)
    {drawn, tinted} = tinted(%{drawn | writer: writer}, view, payload)
    {drawn, overlay} = overlay(drawn, view)
    {drawn, tinted ++ [{"scene", payload} | overlay]}
  end

  defp by_parts(drawn, view, %{world: :server, screen: :client}) do
    {drawn, pictured} = whole(drawn, %{view | screen: [], outlines: []})

    {writer, payload} =
      Scene.write(
        drawn.writer,
        %{view | layers: [], movers: [], labels: [], volumes: []},
        drawn.pane
      )

    {%{drawn | writer: writer}, pictured ++ [{"scene", %{payload | cells: %{}, kinds: []}}]}
  end

  defp tinted(drawn, view, payload) do
    {drawn, arts} = tinted_arts(drawn, view, payload)
    {drawn, cells} = tinted_cells(drawn, view, payload)
    {drawn, arts ++ cells}
  end

  defp tinted_cells(drawn, view, payload) do
    fresh =
      payload.tinted_cells
      |> Enum.map(&{:cell, &1})
      |> Enum.reject(&MapSet.member?(drawn.tinted, &1))

    pushes =
      for {:cell, [base, overlays, tint]} <- fresh,
          built = NetAtlas.tinted_cell(Atlas.fetch(view.atlas).name, base, overlays, tint),
          built != nil,
          do:
            {"tinted_cell",
             %{
               base: base,
               overlays: overlays,
               tint: tint,
               index: built.index,
               png: Base.encode64(built.png)
             }}

    {%{drawn | tinted: Enum.reduce(fresh, drawn.tinted, &MapSet.put(&2, &1))}, pushes}
  end

  defp tinted_arts(drawn, view, payload) do
    fresh = Enum.reject(payload.tints, &MapSet.member?(drawn.tinted, &1))

    pushes =
      for [art, tint] <- fresh,
          built = NetAtlas.tinted(Atlas.fetch(view.atlas).name, art, tint),
          built != nil,
          do:
            {"tinted", %{art: art, tint: tint, index: built.index, png: Base.encode64(built.png)}}

    {%{drawn | tinted: Enum.reduce(fresh, drawn.tinted, &MapSet.put(&2, &1))}, pushes}
  end

  defp whole(drawn, view) do
    case Draw.picture(view, drawn.pane) do
      nil -> {drawn, []}
      raster -> {drawn, [{"picture", pictured_as(drawn.picture, raster)}]}
    end
  end

  defp overlay(drawn, view) do
    key = :erlang.phash2({view.screen, view.outlines, view.focus, drawn.pane, frames(view)})

    if key == drawn.overlay do
      {drawn, []}
    else
      overlay = view |> Draw.screen_picture(drawn.pane) |> overlay_as(drawn.picture)
      {%{drawn | overlay: key}, [{"overlay", overlay}]}
    end
  end

  defp frames(view) do
    atlas = Atlas.fetch(view.atlas)
    now = System.monotonic_time(:millisecond)

    for item <- view.screen,
        elem(item, 0) in [:art, :panel, :bar],
        art = elem(item, 1),
        Atlas.animated?(atlas, art),
        do: Atlas.frame_index(atlas, art, now)
  end

  defp overlay_as(nil, :png), do: ""
  defp overlay_as(nil, _picture), do: nil
  defp overlay_as(raster, picture), do: pictured_as(picture, raster)

  defp pictured_as(:png, raster), do: Picture.png(raster)
  defp pictured_as(:raster, raster), do: raster
end
