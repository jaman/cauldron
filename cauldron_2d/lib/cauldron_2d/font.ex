defmodule Cauldron2D.Font do
  @moduledoc """
  A bitmap font from a game's atlas (`Cauldron2D.Atlas.font!/2`): its glyphs, and how wide a line of text is.

  A pixel font cut from a picture: one glyph per character, laid out as lines of text
  and drawn onto rasters.

      {:ok, sheet} = Cauldron2D.Picture.load("priv/art/font.png")
      font = Cauldron2D.Font.from_sheet(sheet, {8, 10}, " !\\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ")

      Cauldron2D.Font.width(font, "SCORE 120")
      Cauldron2D.Font.layout(font, "PRESS START\\nTO PLAY", align: :centre)
      Cauldron2D.Font.render(font, "GAME OVER", colour: {255, 220, 0, 255}, shadow: {0, 0, 0, 255})

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

  @type glyph() :: Linocut.BitmapFont.glyph()
  @type placement() :: Linocut.BitmapFont.placement()
  @type t() :: Linocut.BitmapFont.t()

  @doc """
  The font in `sheet`, cells `{width, height}` holding `chars` in order; see the module documentation.
  """
  @spec from_sheet(Cauldron2D.Raster.t(), {pos_integer(), pos_integer()}, String.t(), keyword()) ::
          t()
  def from_sheet(sheet, cell, chars, opts \\ []),
    do: Linocut.BitmapFont.from_sheet(sheet, cell, chars, opts)

  @doc """
  The glyph `char` is drawn with, or `nil` when the font has none and no fallback.
  """
  @spec glyph(t(), String.t()) :: glyph() | nil
  def glyph(font, char), do: Linocut.BitmapFont.glyph(font, char)

  @doc """
  How many pixels tall `text` is, its lines one `line` apart.
  """
  @spec height(t(), String.t()) :: pos_integer()
  def height(font, text), do: Linocut.BitmapFont.height(font, text)

  @doc """
  Where each glyph of `text` goes, as `{char, {x, y}}` from the text's top-left corner,
  leaving out characters the font cannot draw.

  Options: `:align` — `:left` (default), `:centre` or `:right`, each line against the
  widest; `:wrap` — a width in pixels at which lines break between words.
  """
  @spec layout(t(), String.t(), keyword()) :: [placement()]
  def layout(font, text, opts \\ []), do: Linocut.BitmapFont.layout(font, text, opts)

  @doc """
  `text` drawn onto a raster just big enough for it.

  Options: `:colour` — `{r, g, b, a}` every glyph pixel is drawn in, keeping its own
  alpha; default the glyphs' own colours. `:shadow` — a colour drawn one pixel down and
  right behind the text. `:outline` — a colour drawn one pixel around it. With `layout/3`'s
  `:align` and `:wrap`.
  """
  @spec render(t(), String.t(), keyword()) :: Cauldron2D.Raster.t()
  def render(font, text, opts \\ []), do: Linocut.BitmapFont.render(font, text, opts)

  @doc """
  The font with every glyph pixel turned white, alpha kept: for drawing it in a colour by multiplying.
  """
  @spec silhouette(t()) :: t()
  def silhouette(font), do: Linocut.BitmapFont.silhouette(font)

  @doc """
  How many pixels across the widest line of `text` is.
  """
  @spec width(t(), String.t()) :: non_neg_integer()
  def width(font, text), do: Linocut.BitmapFont.width(font, text)
end
