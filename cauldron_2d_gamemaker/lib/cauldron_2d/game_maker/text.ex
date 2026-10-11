defmodule Cauldron2D.GameMaker.Text do
  @moduledoc """
  Text in one of a game's fonts, laid out as GameMaker's `draw_text` lays it out, as
  draw list items naming `{:glyph, font, character}` pictures
  (`Cauldron2D.GameMaker.Pictures.table/2`).

      items = Cauldron2D.GameMaker.Text.items(data, "fMenu", "PRESS START", {160, 150},
        halign: :center, colour: {255, 255, 255})

  A `#` or a newline starts a new line, as in GameMaker Studio 1; `\\#` is a `#`; a
  carriage return is dropped. Lines are as tall as the font's tallest glyph unless
  `:separation` says otherwise. Each glyph is drawn `offset` pixels right of
  the pen, which then moves by its `advance` and any kerning with the next character. A
  character the font lacks advances the pen by the width of its space and draws nothing.

  Options:

    * `:halign` — `:left` (the default), `:center` or `:right` of `x`, line by line
    * `:valign` — `:top` (the default), `:middle` or `:bottom` of `y`, for the whole block
    * `:colour` — `{r, g, b}` blended into every glyph; white by default
    * `:alpha` — `0.0`–`1.0`
    * `:mode` — the blend mode, as a draw list item takes it
    * `:depth` — the items' depth
    * `:scale` — `{x, y}`, multiplying every distance and glyph
    * `:angle` — degrees anticlockwise the whole block turns about `{x, y}`, as
      `draw_text_transformed` turns it
    * `:wrap` — a width in pixels: a line wider breaks between words to fit it, as
      `draw_text_ext` does; a word wider on its own keeps a line to itself
    * `:separation` — the distance in pixels from one line's top to the next's

  `width/4` and `height/4` take the same options and measure what `items/5` draws.
  """

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Font

  @type font :: String.t() | non_neg_integer()

  @doc "The draw items of `string` in `font` (a name or an index) at `{x, y}`."
  @spec items(Data.t(), font(), String.t(), {number(), number()}, keyword()) :: [map()]
  def items(%Data{} = data, font, string, {x, y}, opts \\ []) do
    {index, %Font{} = definition} = fetch!(data, font)
    {scale_x, scale_y} = Keyword.get(opts, :scale, {1, 1})
    height = separation(definition, opts)
    lines = lines(definition, string, opts)
    top = y - block_offset(Keyword.get(opts, :valign, :top), length(lines) * height) * scale_y
    style = style(opts)

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, row} ->
      width = line_width(definition, line)
      left = x - line_offset(Keyword.get(opts, :halign, :left), width) * scale_x

      definition
      |> pens(line)
      |> Enum.flat_map(fn {character, pen} ->
        glyph(
          index,
          definition,
          character,
          {left + pen * scale_x, top + row * height * scale_y},
          style
        )
      end)
    end)
    |> turned({x, y}, Keyword.get(opts, :angle, 0))
  end

  defp turned(items, _about, angle) when angle == 0, do: items

  defp turned(items, {x, y}, angle) do
    radians = angle * :math.pi() / 180
    {cos, sin} = {:math.cos(radians), :math.sin(radians)}

    Enum.map(items, fn %{position: {px, py}} = item ->
      {dx, dy} = {px - x, py - y}
      %{item | position: {x + dx * cos + dy * sin, y - dx * sin + dy * cos}}
    end)
  end

  @doc "The width in pixels of the widest line of `string` in `font`, unscaled."
  @spec width(Data.t(), font(), String.t(), keyword()) :: number()
  def width(%Data{} = data, font, string, opts \\ []) do
    {_index, definition} = fetch!(data, font)

    definition
    |> lines(string, opts)
    |> Enum.map(&line_width(definition, &1))
    |> Enum.max(fn -> 0 end)
  end

  @doc "The height in pixels of `string` in `font`, unscaled: its line count times the line separation."
  @spec height(Data.t(), font(), String.t(), keyword()) :: number()
  def height(%Data{} = data, font, string, opts \\ []) do
    {_index, definition} = fetch!(data, font)
    length(lines(definition, string, opts)) * separation(definition, opts)
  end

  defp fetch!(%Data{fonts: fonts}, index) when is_integer(index),
    do: {index, Enum.fetch!(fonts, index)}

  defp fetch!(%Data{} = data, name) do
    case Data.index(data, :fonts, name) do
      nil -> raise ArgumentError, "the game has no font named #{inspect(name)}"
      index -> {index, Enum.at(data.fonts, index)}
    end
  end

  defp style(opts) do
    opts
    |> Keyword.take([:alpha, :depth, :scale, :angle, :mode])
    |> Map.new()
    |> Map.put(:blend, Keyword.get(opts, :colour, {255, 255, 255}))
  end

  defp lines(font, string, opts) do
    string
    |> String.replace("\r", "")
    |> String.replace("\\#", <<0>>)
    |> String.split(["#", "\n"])
    |> Enum.map(&(&1 |> String.replace(<<0>>, "#") |> String.to_charlist()))
    |> Enum.flat_map(&wrap(font, &1, Keyword.get(opts, :wrap)))
  end

  defp wrap(_font, line, nil), do: [line]

  defp wrap(font, line, width) do
    line
    |> Enum.chunk_by(&(&1 == ?\s))
    |> Enum.reduce([[]], fn piece, [current | done] ->
      joined = current ++ piece

      cond do
        current == [] -> [piece | done]
        line_width(font, :string.trim(joined, :trailing)) <= width -> [joined | done]
        hd(piece) == ?\s -> [[], :string.trim(current, :trailing) | done]
        true -> [piece, :string.trim(current, :trailing) | done]
      end
    end)
    |> then(fn [last | done] -> [:string.trim(last, :trailing) | done] end)
    |> Enum.reverse()
    |> Enum.map(&List.flatten/1)
  end

  defp separation(font, opts),
    do: Keyword.get_lazy(opts, :separation, fn -> line_height(font) end)

  defp line_height(%Font{glyphs: glyphs}) do
    glyphs
    |> Map.values()
    |> Enum.map(fn %{source: {_x, _y, _width, height}} -> height end)
    |> Enum.max(fn -> 0 end)
  end

  defp pens(%Font{} = font, characters) do
    {placed, _end} =
      characters
      |> Enum.zip(tl(characters ++ [nil]))
      |> Enum.map_reduce(0, fn {character, next}, pen ->
        {{character, pen}, pen + advance(font, character, next)}
      end)

    placed
  end

  defp line_width(%Font{} = font, characters) do
    characters
    |> Enum.zip(tl(characters ++ [nil]))
    |> Enum.reduce(0, fn {character, next}, total -> total + advance(font, character, next) end)
  end

  defp advance(%Font{glyphs: glyphs} = font, character, next) do
    case Map.fetch(glyphs, character) do
      {:ok, %{advance: advance, kerning: kerning}} -> advance + Map.get(kerning, next, 0)
      :error -> space(font)
    end
  end

  defp space(%Font{glyphs: glyphs}) do
    case Map.fetch(glyphs, ?\s) do
      {:ok, %{advance: advance}} -> advance
      :error -> 0
    end
  end

  defp glyph(index, %Font{glyphs: glyphs}, character, {x, y}, style) do
    case Map.fetch(glyphs, character) do
      {:ok, %{source: {_sx, _sy, width, height}, offset: offset}} when width > 0 and height > 0 ->
        {scale_x, _} = Map.get(style, :scale, {1, 1})

        [
          Map.merge(style, %{
            picture: {:glyph, index, character},
            position: {x + offset * scale_x, y}
          })
        ]

      _blank ->
        []
    end
  end

  defp line_offset(:left, _width), do: 0
  defp line_offset(:center, width), do: width / 2
  defp line_offset(:right, width), do: width

  defp block_offset(:top, _height), do: 0
  defp block_offset(:middle, height), do: height / 2
  defp block_offset(:bottom, height), do: height
end
