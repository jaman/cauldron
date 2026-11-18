defmodule Cauldron2D.Screen do
  @moduledoc """
  What a scene draws fixed to the pane rather than to the world: the hud, a menu, a
  title, a message. A scene's `:screen` is a list of items in pixels of the game's own
  art, placed against the pane's edges, drawn over the world and its front layers.

      screen: [
        {:panel, :frame, {4, 4}, {120, 28}, border: 4},
        {:art, :heart, {10, 10}},
        {:text, :big, "SCORE \#{score}", {-8, 8}, anchor: :top_right, colour: {255, 220, 96}},
        {:bar, :shield_bar, {10, 22}, shields / 5},
        {:fill, {0, 0}, :pane, {0, 0, 0, 160}},
        {:text, :big, "PAUSED", {0, 0}, anchor: :centre, outline: {0, 0, 0}}
      ]

  ## Items

    * `{:art, art, {x, y}, opts}` — an art of the atlas, at the frame showing
    * `{:text, font, text, {x, y}, opts}` — text in a font the atlas holds
      (`Cauldron2D.Atlas.put_font/3`). Options `:colour` (`{r, g, b}`, the glyphs drawn
      in it; default their own colours), `:shadow` and `:outline` (`{r, g, b}`), and
      `Cauldron2D.Font.layout/3`'s `:align` and `:wrap`
    * `{:panel, art, {x, y}, {width, height}, opts}` — an art stretched to a size by
      nine slices: its corners kept, its edges and middle repeated. Option `:border`,
      the corners' size in pixels (default a third of the art's smaller side)
    * `{:bar, art, {x, y}, fraction, opts}` — an art shown up to `fraction` (`0.0..1.0`)
      of its width, or of its height with `direction: :up`
    * `{:fill, {x, y}, {width, height} | :pane, {r, g, b, a}}` — a rectangle of colour
    * `{:box, {x, y}, {width, height}, {r, g, b, a}, opts}` — a rectangle's edges only,
      `:thickness` pixels wide (default `1`): an outline, such as a hit box drawn to check
      it (a scene's `:outlines` become these)

  The trailing `opts` may be left off. Every item takes `:anchor` — which point of the
  pane `{x, y}` is measured from, and which point of the item lands there: `:top_left`
  (default), `:top`, `:top_right`, `:left`, `:centre`, `:right`, `:bottom_left`,
  `:bottom`, `:bottom_right` — `:pivot`, the point of the item that lands there when it
  is not the anchor's (a row of a box anchored at the pane's centre places its own
  top-left corner), and `:alpha` (`0.0..1.0`). `:art`, `:panel` and `:bar`
  take `:tint`, an `{r, g, b}` multiplied into their colours. `:art`, `:panel`, `:bar`
  and `:text` take `:scale`, a whole number of pixels for each of the picture's, a
  text's outline and shadow growing with it.

  `compose/4` draws the items onto a transparent raster the pane's size; front ends
  call it and lay the raster over the world at the scale the world is drawn.
  """

  alias Cauldron2D.{Atlas, DrawList, Font, Raster}

  @type anchor ::
          :top_left
          | :top
          | :top_right
          | :left
          | :centre
          | :right
          | :bottom_left
          | :bottom
          | :bottom_right
  @type point :: {number(), number()}
  @type item ::
          {:art, Atlas.art(), point()}
          | {:art, Atlas.art(), point(), keyword()}
          | {:text, atom(), String.t(), point()}
          | {:text, atom(), String.t(), point(), keyword()}
          | {:panel, Atlas.art(), point(), {pos_integer(), pos_integer()}}
          | {:panel, Atlas.art(), point(), {pos_integer(), pos_integer()}, keyword()}
          | {:bar, Atlas.art(), point(), number()}
          | {:bar, Atlas.art(), point(), number(), keyword()}
          | {:fill, point(), {pos_integer(), pos_integer()} | :pane, Atlas.rgba()}
          | {:box, point(), {number(), number()}, Atlas.rgba()}
          | {:box, point(), {number(), number()}, Atlas.rgba(), keyword()}

  @doc """
  `items` drawn onto a transparent raster `{width, height}` pixels, with animated arts
  at the frame showing at `at` milliseconds.
  """
  @spec compose(Atlas.name() | Atlas.t(), [item()], {pos_integer(), pos_integer()}, keyword()) ::
          Raster.t()
  def compose(atlas, items, {width, height} = size, opts \\ []) do
    atlas = Atlas.fetch(atlas)
    at = Keyword.get(opts, :at, 0)
    drawn = Enum.flat_map(items, &draw_items(atlas, &1, size, at))

    DrawList.render(drawn, {max(width, 1), max(height, 1)}, & &1, Keyword.take(opts, [:native]))
  end

  @doc "The size in pixels `item` covers, before `:scale`."
  @spec size(Atlas.name() | Atlas.t(), item(), {pos_integer(), pos_integer()}) ::
          {non_neg_integer(), non_neg_integer()}
  def size(atlas, item, pane), do: atlas |> Atlas.fetch() |> measure(normal(item), pane)

  @doc "The pane pixel `item`'s top-left corner lands on, after its anchor and `:scale`."
  @spec origin(Atlas.name() | Atlas.t(), item(), {pos_integer(), pos_integer()}) :: point()
  def origin(atlas, item, pane) do
    atlas = Atlas.fetch(atlas)
    {kind, opts} = normal(item)
    extent = scaled(measure(atlas, {kind, opts}, pane), opts)
    placed(opts, extent, pane)
  end

  @doc "How far across and down the pane an anchor stands, each `0.0..1.0`."
  @spec fractions(anchor()) :: {float(), float()}
  def fractions(:top_left), do: {0.0, 0.0}
  def fractions(:top), do: {0.5, 0.0}
  def fractions(:top_right), do: {1.0, 0.0}
  def fractions(:left), do: {0.0, 0.5}
  def fractions(:centre), do: {0.5, 0.5}
  def fractions(:right), do: {1.0, 0.5}
  def fractions(:bottom_left), do: {0.0, 1.0}
  def fractions(:bottom), do: {0.5, 1.0}
  def fractions(:bottom_right), do: {1.0, 1.0}

  defp draw_items(atlas, item, pane, at) do
    {kind, opts} = normal(item)
    extent = scaled(measure(atlas, {kind, opts}, pane), opts)
    origin = placed(opts, extent, pane)
    pieces(atlas, kind, Map.put(opts, :extent, extent), origin, at)
  end

  defp normal({:art, art, at}), do: normal({:art, art, at, []})
  defp normal({:art, art, at, opts}), do: {:art, %{art: art, at: at, opts: opts}}
  defp normal({:text, font, text, at}), do: normal({:text, font, text, at, []})

  defp normal({:text, font, text, at, opts}),
    do: {:text, %{font: font, text: text, at: at, opts: opts}}

  defp normal({:panel, art, at, size}), do: normal({:panel, art, at, size, []})

  defp normal({:panel, art, at, size, opts}),
    do: {:panel, %{art: art, at: at, size: size, opts: opts}}

  defp normal({:bar, art, at, fraction}), do: normal({:bar, art, at, fraction, []})

  defp normal({:bar, art, at, fraction, opts}),
    do: {:bar, %{art: art, at: at, fraction: fraction |> max(0.0) |> min(1.0), opts: opts}}

  defp normal({:fill, at, size, colour}),
    do: {:fill, %{at: at, size: size, colour: colour, opts: []}}

  defp normal({:box, at, size, colour}), do: normal({:box, at, size, colour, []})

  defp normal({:box, at, {width, height}, colour, opts}),
    do: {:box, %{at: at, size: {round(width), round(height)}, colour: colour, opts: opts}}

  defp measure(atlas, {:art, %{art: art}}, _pane), do: Atlas.entry(atlas, art).size
  defp measure(_atlas, {:panel, %{size: size}}, _pane), do: size
  defp measure(_atlas, {:fill, %{size: :pane}}, pane), do: pane
  defp measure(_atlas, {:fill, %{size: size}}, _pane), do: size
  defp measure(_atlas, {:box, %{size: size}}, _pane), do: size

  defp measure(atlas, {:bar, %{art: art, fraction: fraction, opts: opts}}, _pane) do
    {width, height} = Atlas.entry(atlas, art).size

    if Keyword.get(opts, :direction, :right) == :up,
      do: {width, round(height * fraction)},
      else: {round(width * fraction), height}
  end

  defp measure(atlas, {:text, %{font: font, text: text, opts: opts}}, _pane) do
    font = Atlas.font!(atlas, font)
    placements = Font.layout(font, text, opts)
    grow = if opts[:outline], do: 2, else: if(opts[:shadow], do: 1, else: 0)

    Enum.reduce(placements, {0, font.height + grow}, fn {char, {x, y}}, {width, height} ->
      %{raster: raster} = Font.glyph(font, char)
      {max(width, x + raster.width + grow), max(height, y + raster.height + grow)}
    end)
  end

  defp scaled({width, height}, %{opts: opts}) do
    scale = Keyword.get(opts, :scale, 1)
    {width * scale, height * scale}
  end

  defp placed(%{at: {x, y}, opts: opts}, {width, height}, {pane_width, pane_height}) do
    anchor = Keyword.get(opts, :anchor, :top_left)
    {across, down} = fractions(anchor)
    {pivot_across, pivot_down} = fractions(Keyword.get(opts, :pivot, anchor))
    {pane_width * across + x - width * pivot_across, pane_height * down + y - height * pivot_down}
  end

  defp pieces(atlas, :art, %{art: art, opts: opts}, origin, at),
    do: [picture(Atlas.frame_at(atlas, art, at).raster, origin, opts)]

  defp pieces(atlas, :bar, %{art: art, opts: opts} = bar, origin, at) do
    raster = Atlas.frame_at(atlas, art, at).raster

    case measure(atlas, {:bar, bar}, nil) do
      {0, _height} -> []
      {_width, 0} -> []
      shown -> [picture(clip(raster, shown, Keyword.get(opts, :direction, :right)), origin, opts)]
    end
  end

  defp pieces(atlas, :panel, %{art: art, size: size, opts: opts}, origin, at) do
    raster = Atlas.frame_at(atlas, art, at).raster
    border = Keyword.get(opts, :border, div(min(raster.width, raster.height), 3))
    scale = Keyword.get(opts, :scale, 1)

    raster
    |> Linocut.Slices.nine(border, {div(elem(size, 0), scale), div(elem(size, 1), scale)})
    |> then(&[picture(&1, origin, opts)])
  end

  defp pieces(_atlas, :fill, %{colour: {r, g, b, a}, extent: extent}, origin, _at),
    do: [%{picture: Raster.from_rgba(1, 1, <<r, g, b, a>>), position: origin, scale: extent}]

  defp pieces(
         _atlas,
         :box,
         %{colour: {r, g, b, a}, extent: {width, height}, opts: opts},
         {x, y},
         _at
       ) do
    edge = min(Keyword.get(opts, :thickness, 1), max(1, div(min(width, height), 2)))
    dot = Raster.from_rgba(1, 1, <<r, g, b, a>>)

    for {position, size} <- [
          {{x, y}, {width, edge}},
          {{x, y + height - edge}, {width, edge}},
          {{x, y + edge}, {edge, height - 2 * edge}},
          {{x + width - edge, y + edge}, {edge, height - 2 * edge}}
        ],
        elem(size, 0) > 0 and elem(size, 1) > 0,
        do: %{picture: dot, position: position, scale: size}
  end

  defp pieces(atlas, :text, %{font: name, text: text, opts: opts}, {left, top}, _at) do
    font = Atlas.font!(atlas, name)
    white = Atlas.white_font!(atlas, name)
    placements = Font.layout(font, text, opts)
    look = %{alpha: Keyword.get(opts, :alpha, 1.0), scale: Keyword.get(opts, :scale, 1)}
    inset = if opts[:outline], do: look.scale, else: 0
    {x, y} = {left + inset, top + inset}

    ring(white, placements, opts[:outline], {x, y}, look) ++
      glyphs(white, placements, opts[:shadow], {x + look.scale, y + look.scale}, look) ++
      lettered(font, white, placements, opts[:colour], {x, y}, look)
  end

  defp ring(_font, _placements, nil, _origin, _look), do: []

  defp ring(font, placements, colour, {left, top}, look) do
    for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0} do
      glyphs(font, placements, colour, {left + dx * look.scale, top + dy * look.scale}, look)
    end
    |> List.flatten()
  end

  defp lettered(font, _white, placements, nil, origin, look),
    do: glyphs(font, placements, :own, origin, look)

  defp lettered(_font, white, placements, colour, origin, look),
    do: glyphs(white, placements, colour, origin, look)

  defp glyphs(_font, _placements, nil, _origin, _look), do: []

  defp glyphs(font, placements, colour, {left, top}, %{alpha: alpha, scale: scale}) do
    for {char, {x, y}} <- placements do
      %{
        picture: Font.glyph(font, char).raster,
        position: {left + x * scale, top + y * scale},
        scale: {scale, scale},
        alpha: alpha
      }
      |> blend(colour)
    end
  end

  defp blend(item, :own), do: item
  defp blend(item, {r, g, b}), do: Map.put(item, :blend, {r, g, b})

  defp picture(raster, position, opts) do
    scale = Keyword.get(opts, :scale, 1)

    %{
      picture: raster,
      position: position,
      scale: {scale, scale},
      alpha: Keyword.get(opts, :alpha, 1.0)
    }
    |> then(fn item ->
      case Keyword.get(opts, :tint) do
        nil -> item
        tint -> Map.put(item, :blend, tint)
      end
    end)
  end

  defp clip(raster, {width, height}, :up),
    do: Raster.crop(raster, {0, raster.height - height}, {width, height})

  defp clip(raster, {width, height}, _direction), do: Raster.crop(raster, {0, 0}, {width, height})
end
