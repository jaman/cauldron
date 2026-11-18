defmodule Linocut.BitmapFont do
  @moduledoc """
  A pixel font cut from a picture: one glyph per character, laid out as lines of text
  and drawn onto rasters.

      {:ok, sheet} = Linocut.load("priv/art/font.png")
      font = Linocut.BitmapFont.from_sheet(sheet, {8, 10}, " !\\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ")

      Linocut.BitmapFont.width(font, "SCORE 120")
      Linocut.BitmapFont.layout(font, "PRESS START\\nTO PLAY", align: :centre)
      Linocut.BitmapFont.render(font, "GAME OVER", colour: {255, 220, 0, 255}, shadow: {0, 0, 0, 255})

  ## The sheet

  The sheet is a grid of cells `{width, height}` pixels, read left to right and top to
  bottom, one character of `chars` in each, in order. A glyph is its cell's picture,
  trimmed of the empty columns on its right unless `fixed: true`, so the font is
  proportional; a glyph with nothing in it (the space) keeps `:space` columns.

  ## Options of `from_sheet/4`

    * `:spacing` — empty columns between glyphs. Default `1`
    * `:space` — the advance of a glyph with no pixels, in pixels. Default half the cell
    * `:line` — pixels from one line's top to the next. Default the cell's height + 1
    * `:fixed` — every glyph advances the cell's width. Default `false`
    * `:fallback` — the character drawn for one the font lacks. Default `"?"` when the font
      has it, else none: the character is skipped
    * `:upcase` — lowercase letters the font lacks are drawn as capitals. Default `true`

  Characters are graphemes; `"\\n"` breaks a line.
  """

  alias FrenchCurve.Raster

  @type glyph :: %{raster: Raster.t(), advance: non_neg_integer()}
  @type t :: %__MODULE__{
          glyphs: %{String.t() => glyph()},
          height: pos_integer(),
          line: pos_integer(),
          spacing: non_neg_integer(),
          fallback: String.t() | nil,
          upcase?: boolean()
        }
  @type placement :: {String.t(), {integer(), integer()}}

  @enforce_keys [:glyphs, :height, :line]
  defstruct [:glyphs, :height, :line, spacing: 1, fallback: nil, upcase?: true]

  @doc "The font in `sheet`, cells `{width, height}` holding `chars` in order; see the module documentation."
  @spec from_sheet(Raster.t(), {pos_integer(), pos_integer()}, String.t(), keyword()) :: t()
  def from_sheet(%Raster{} = sheet, {cell_width, cell_height} = cell, chars, opts \\ []) do
    across = div(sheet.width, cell_width)
    fixed? = Keyword.get(opts, :fixed, false)
    space = Keyword.get(opts, :space, div(cell_width, 2))

    glyphs =
      chars
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.take(across * div(sheet.height, cell_height))
      |> Map.new(fn {char, index} ->
        origin = {rem(index, across) * cell_width, div(index, across) * cell_height}
        {char, cut(sheet, origin, cell, fixed?, space)}
      end)

    fallback = Keyword.get(opts, :fallback, if(Map.has_key?(glyphs, "?"), do: "?"))

    %__MODULE__{
      glyphs: glyphs,
      height: cell_height,
      line: Keyword.get(opts, :line, cell_height + 1),
      spacing: Keyword.get(opts, :spacing, 1),
      fallback: fallback,
      upcase?: Keyword.get(opts, :upcase, true)
    }
  end

  @doc "The glyph `char` is drawn with, or `nil` when the font has none and no fallback."
  @spec glyph(t(), String.t()) :: glyph() | nil
  def glyph(%__MODULE__{glyphs: glyphs} = font, char) do
    Map.get(glyphs, char) ||
      (font.upcase? && Map.get(glyphs, String.upcase(char))) ||
      (font.fallback && Map.get(glyphs, font.fallback))
  end

  @doc "How many pixels across the widest line of `text` is."
  @spec width(t(), String.t()) :: non_neg_integer()
  def width(%__MODULE__{} = font, text) do
    text |> String.split("\n") |> Enum.map(&line_width(font, &1)) |> Enum.max(fn -> 0 end)
  end

  @doc "How many pixels tall `text` is, its lines one `line` apart."
  @spec height(t(), String.t()) :: pos_integer()
  def height(%__MODULE__{} = font, text) do
    lines = text |> String.split("\n") |> length()
    (lines - 1) * font.line + font.height
  end

  @doc """
  Where each glyph of `text` goes, as `{char, {x, y}}` from the text's top-left corner,
  leaving out characters the font cannot draw.

  Options: `:align` — `:left` (default), `:centre` or `:right`, each line against the
  widest; `:wrap` — a width in pixels at which lines break between words.
  """
  @spec layout(t(), String.t(), keyword()) :: [placement()]
  def layout(%__MODULE__{} = font, text, opts \\ []) do
    lines = text |> String.split("\n") |> Enum.flat_map(&wrapped(font, &1, opts[:wrap]))
    widest = lines |> Enum.map(&line_width(font, &1)) |> Enum.max(fn -> 0 end)
    align = Keyword.get(opts, :align, :left)

    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, row} ->
      start = indent(align, widest, line_width(font, line))
      placed(font, line, {start, row * font.line})
    end)
  end

  @doc """
  `text` drawn onto a raster just big enough for it.

  Options: `:colour` — `{r, g, b, a}` every glyph pixel is drawn in, keeping its own
  alpha; default the glyphs' own colours. `:shadow` — a colour drawn one pixel down and
  right behind the text. `:outline` — a colour drawn one pixel around it. With `layout/3`'s
  `:align` and `:wrap`.
  """
  @spec render(t(), String.t(), keyword()) :: Raster.t()
  def render(%__MODULE__{} = font, text, opts \\ []) do
    placements = layout(font, text, opts)
    margin = if opts[:outline], do: 1, else: 0
    extra = if opts[:shadow] || opts[:outline], do: 1, else: 0
    {width, height} = extent(font, placements)
    canvas = Raster.new(width + margin + extra, height + margin + extra)
    shift = fn {x, y}, {dx, dy} -> {x + margin + dx, y + margin + dy} end

    canvas
    |> stamp_ring(font, placements, opts[:outline], shift)
    |> stamp(font, placements, opts[:shadow], &shift.(&1, {1, 1}))
    |> stamp(font, placements, opts[:colour], &shift.(&1, {0, 0}))
  end

  @doc "The font with every glyph pixel turned white, alpha kept: for drawing it in a colour by multiplying."
  @spec silhouette(t()) :: t()
  def silhouette(%__MODULE__{} = font) do
    glyphs =
      Map.new(font.glyphs, fn {char, glyph} ->
        {char, %{glyph | raster: whitened(glyph.raster)}}
      end)

    %{font | glyphs: glyphs}
  end

  defp cut(sheet, origin, {cell_width, cell_height}, fixed?, space) do
    raster = Raster.crop(sheet, origin, {cell_width, cell_height})
    used = last_column(raster) + 1

    cond do
      fixed? -> %{raster: raster, advance: cell_width}
      used == 0 -> %{raster: Raster.new(1, cell_height), advance: space}
      true -> %{raster: Raster.crop(raster, {0, 0}, {used, cell_height}), advance: used}
    end
  end

  defp last_column(%Raster{width: width, height: height} = raster) do
    rgba = Raster.to_rgba_binary(raster)

    Enum.find((width - 1)..0//-1, -1, fn x ->
      Enum.any?(0..(height - 1), fn y -> :binary.at(rgba, (y * width + x) * 4 + 3) > 0 end)
    end)
  end

  defp line_width(font, line) do
    case advances(font, line) do
      [] -> 0
      advances -> Enum.sum(advances) + font.spacing * (length(advances) - 1)
    end
  end

  defp advances(font, line) do
    for char <- String.graphemes(line), glyph = glyph(font, char), do: glyph.advance
  end

  defp wrapped(_font, line, nil), do: [line]

  defp wrapped(font, line, width) do
    line
    |> String.split(" ")
    |> Enum.reduce([], fn
      word, [] -> [word]
      word, [current | done] -> fit(font, width, current, word, done)
    end)
    |> Enum.reverse()
  end

  defp fit(font, width, current, word, done) do
    joined = current <> " " <> word
    if line_width(font, joined) <= width, do: [joined | done], else: [word, current | done]
  end

  defp indent(:left, _widest, _width), do: 0
  defp indent(:centre, widest, width), do: div(widest - width, 2)
  defp indent(:right, widest, width), do: widest - width

  defp placed(font, line, {start, top}) do
    line
    |> String.graphemes()
    |> Enum.reduce({start, []}, fn char, {x, acc} ->
      case glyph(font, char) do
        nil -> {x, acc}
        glyph -> {x + glyph.advance + font.spacing, [{char, {x, top}} | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp extent(font, placements) do
    Enum.reduce(placements, {1, font.height}, fn {char, {x, y}}, {width, height} ->
      %{raster: raster} = glyph(font, char)
      {max(width, x + raster.width), max(height, y + raster.height)}
    end)
  end

  defp stamp_ring(canvas, _font, _placements, nil, _shift), do: canvas

  defp stamp_ring(canvas, font, placements, colour, shift) do
    for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0}, reduce: canvas do
      acc -> stamp(acc, font, placements, colour, &shift.(&1, {dx, dy}))
    end
  end

  defp stamp(canvas, font, placements, colour, at) do
    Enum.reduce(placements, canvas, fn {char, position}, acc ->
      {x, y} = at.(position)
      paint(acc, glyph(font, char).raster, {x, y}, colour)
    end)
  end

  defp paint(canvas, %Raster{width: width} = raster, {left, top}, colour) do
    raster
    |> Raster.to_rgba_binary()
    |> pixels(width)
    |> Enum.reduce(canvas, fn {{x, y}, {r, g, b, a}}, acc ->
      Raster.put_pixel(acc, left + x, top + y, coloured({r, g, b, a}, colour))
    end)
  end

  defp pixels(rgba, width) do
    for {<<r, g, b, a>>, index} <- Enum.with_index(chunks(rgba)),
        a > 0,
        do: {{rem(index, width), div(index, width)}, {r, g, b, a}}
  end

  defp chunks(rgba), do: for(<<pixel::binary-4 <- rgba>>, do: pixel)

  defp coloured(pixel, nil), do: pixel
  defp coloured({_r, _g, _b, a}, {r, g, b, ca}), do: {r, g, b, div(a * ca, 255)}

  defp whitened(%Raster{width: width, height: height} = raster) do
    rgba =
      for <<_r, _g, _b, a <- Raster.to_rgba_binary(raster)>>, into: <<>>, do: <<255, 255, 255, a>>

    Raster.from_rgba(width, height, rgba)
  end
end
