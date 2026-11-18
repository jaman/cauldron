defmodule Cauldron2D.Drafter.Surface.ScreenLayer do
  @moduledoc """
  A scene's `:screen` (`Cauldron2D.Screen`) on a `Cauldron2D.Drafter.Surface`, in each
  way the surface draws.

    * `over/3` — laid over a composed frame, in the frame's own pixels
    * `placement/4` — on a kitty terminal that keeps images, an image of its own placed
      over the pane above every sprite, sent again only when it changes
    * `glyphs/4` — in plain glyphs, its text written as characters and its arts as their
      glyphs, at the cells nearest their pixels
  """

  alias Cauldron2D.{Atlas, Raster, Screen, Surface}
  alias Drafter.Terminal.ANSI
  alias FrenchCurve.Backend.Kitty

  @layer 3
  @placement 1

  @doc "`raster` with `items` drawn over it in its own pixels, the clock at `at` milliseconds."
  @spec over(Raster.t(), Atlas.name(), [Screen.item()], integer()) :: Raster.t()
  def over(raster, _atlas, [], _at), do: raster

  def over(%FrenchCurve.Raster{} = raster, atlas, items, at),
    do: Surface.stack(raster, Screen.compose(atlas, items, Raster.dimensions(raster), at: at))

  @doc """
  The bytes that show `items` over a pane `fit` `{columns, rows}` cells at `rect`, drawn
  at `size` pixels, under image `id`, and the bytes that take it away. The image is sent
  again only when what it shows changes; with no items, any image shown before is removed.
  """
  @spec placement(Atlas.name(), [Screen.item()], term(), map()) :: {iodata(), iodata()}
  def placement(atlas, items, id, %{size: size, fit: fit, rect: rect, at: at, compress: compress}) do
    image = FrenchCurve.image_id({id, :screen})
    clear = Kitty.delete(id: image)
    key = {__MODULE__, id}

    case items do
      [] ->
        shown? = Process.get(key) != nil
        Process.delete(key)
        {if(shown?, do: clear, else: []), []}

      items ->
        raster = Screen.compose(atlas, items, size, at: at)
        digest = :erlang.phash2({Raster.to_rgba_binary(raster), size, fit})
        sent = if Process.get(key) == digest, do: [], else: transmitted(raster, image, compress)
        Process.put(key, digest)

        {[sent, ANSI.cursor_to(rect.x + 1, rect.y + 1), place(image, fit)], [clear]}
    end
  end

  @doc """
  Glyph `rows` — rows of `{glyph, colour}` cells two characters wide — with `items` written
  over them, a tile `tile` pixels square drawn as one row and two characters.
  """
  @spec glyphs([[{String.t(), term()}]], Atlas.name(), [Screen.item()], pos_integer()) ::
          [[{String.t(), term()}]]
  def glyphs(rows, _atlas, [], _tile), do: rows

  def glyphs([first | _] = rows, atlas, items, tile) do
    pane = {length(first) * tile, length(rows) * tile}
    atlas = Atlas.fetch(atlas)

    Enum.reduce(items, rows, fn item, acc ->
      case lettering(atlas, item) do
        nil -> acc
        {text, colour} -> write(acc, text, colour, cell_of(atlas, item, pane, tile))
      end
    end)
  end

  def glyphs([], _atlas, _items, _tile), do: []

  defp transmitted(raster, image, compress),
    do: [Kitty.delete(id: image), Kitty.transmit(raster, image, compress: compress)]

  defp place(image, fit), do: Kitty.place(image, placement: @placement, fit: fit, z: @layer)

  defp lettering(_atlas, {:text, _font, text, _at}), do: {text, nil}
  defp lettering(_atlas, {:text, _font, text, _at, opts}), do: {text, rgb(opts[:colour])}
  defp lettering(atlas, {:art, art, _at}), do: art_glyph(atlas, art)
  defp lettering(atlas, {:art, art, _at, _opts}), do: art_glyph(atlas, art)
  defp lettering(_atlas, _item), do: nil

  defp art_glyph(atlas, art) do
    entry = Atlas.entry(atlas, art)
    {entry.glyph, entry.color}
  end

  defp rgb(nil), do: nil
  defp rgb({r, g, b}), do: {r, g, b}

  defp cell_of(atlas, item, pane, tile) do
    {left, top} = Screen.origin(atlas, item, pane)
    {round(left * 2 / tile), round(top / tile)}
  end

  defp write(rows, text, colour, {column, row}) when row >= 0 and row < length(rows),
    do: List.update_at(rows, row, &lettered(&1, text, colour, column))

  defp write(rows, _text, _colour, _cell), do: rows

  defp lettered(cells, text, colour, column) do
    chars =
      Enum.flat_map(cells, fn {glyph, c} -> for char <- String.graphemes(glyph), do: {char, c} end)

    text
    |> String.graphemes()
    |> Enum.with_index(column)
    |> Enum.reduce(chars, &put_char(&1, &2, colour))
  end

  defp put_char({char, index}, chars, colour) when index >= 0 and index < length(chars),
    do: List.replace_at(chars, index, {char, colour || elem(Enum.at(chars, index), 1)})

  defp put_char(_char, chars, _colour), do: chars
end
