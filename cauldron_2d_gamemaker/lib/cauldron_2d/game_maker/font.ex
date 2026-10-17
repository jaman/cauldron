defmodule Cauldron2D.GameMaker.Font do
  @moduledoc """
  A font (a `FONT` entry): glyphs cut from one picture on a texture page.

  `picture` is the `Cauldron2D.GameMaker.Region` holding every glyph. Each glyph in
  `glyphs`, keyed by its character's code point, is a map of `source`
  `{x, y, width, height}` inside that picture, `advance` (pixels the pen moves after
  it), `offset` (pixels right of the pen it is drawn) and `kerning`, a map from the
  next character's code point to an extra advance. `size` is the point size it was
  made at, from the typeface `typeface`.

  `ascender` is the font's ascender height in pixels from GameMaker 2022.2 on,
  `sdf_spread` the signed-distance-field spread from 2023.2 on and `line_height` the
  line height from 2023.6 on; each is `nil` in files written before that version.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.General
  alias Cauldron2D.GameMaker.Region

  @enforce_keys [:name, :picture, :glyphs]
  defstruct [
    :name,
    :typeface,
    :size,
    :bold,
    :italic,
    :picture,
    :scale,
    :ascender,
    :sdf_spread,
    :line_height,
    glyphs: %{}
  ]

  @type glyph :: %{
          source: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()},
          advance: integer(),
          offset: integer(),
          kerning: %{non_neg_integer() => integer()}
        }
  @type t :: %__MODULE__{
          name: String.t(),
          typeface: String.t() | nil,
          size: number(),
          bold: boolean(),
          italic: boolean(),
          picture: Region.t() | nil,
          scale: {number(), number()},
          ascender: non_neg_integer() | nil,
          sdf_spread: non_neg_integer() | nil,
          line_height: non_neg_integer() | nil,
          glyphs: %{non_neg_integer() => glyph()}
        }

  @doc "The font at `at`; `general` says where its glyph list sits and what each glyph carries."
  @spec read(binary(), non_neg_integer(), %{non_neg_integer() => Region.t()}, General.t()) ::
          t()
  def read(data, at, regions, %General{} = general) do
    <<_name::little-32, _typeface::little-32, size::binary-4, bold::little-32, italic::little-32,
      _range::binary-8, picture::little-32, scale_x::binary-4, scale_y::binary-4>> =
      binary_part(data, at, 40)

    extras = extras(general)
    values = Bytes.u32s(data, at + 40, length(extras))
    fields = extras |> Enum.zip(values) |> Map.new()
    glyphs_at = at + 40 + 4 * length(extras)

    %__MODULE__{
      name: Bytes.string_at(data, at),
      typeface: Bytes.string_at(data, at + 4),
      size: size(size),
      bold: bold != 0,
      italic: italic != 0,
      picture: Map.get(regions, picture),
      scale: {Bytes.float(scale_x), Bytes.float(scale_y)},
      ascender: Map.get(fields, :ascender),
      sdf_spread: Map.get(fields, :sdf_spread),
      line_height: Map.get(fields, :line_height),
      glyphs: glyphs(data, glyphs_at, glyph_padding(general))
    }
  end

  defp extras(%General{bytecode: bytecode} = general) do
    [
      {bytecode >= 17, :ascender_offset},
      {General.at_least?(general, 2022, 2), :ascender},
      {General.current_at_least?(general, 2023, 2), :sdf_spread},
      {General.at_least?(general, 2023, 6), :line_height}
    ]
    |> Enum.filter(fn {present?, _name} -> present? end)
    |> Enum.map(fn {_present?, name} -> name end)
  end

  defp glyph_padding(general), do: if(General.at_least?(general, 2024, 11), do: 2, else: 0)

  defp size(<<value::little-signed-32>>) when value >= 0, do: value
  defp size(bits), do: abs(Bytes.float(bits))

  defp glyphs(data, at, padding) do
    data
    |> Bytes.pointers(at)
    |> Map.new(fn pointer -> glyph(data, pointer, padding) end)
  end

  defp glyph(data, at, padding) do
    <<character::little-16, x::little-16, y::little-16, width::little-16, height::little-16,
      advance::little-signed-16, offset::little-signed-16, _padding::binary-size(padding),
      pairs::little-16>> = binary_part(data, at, 16 + padding)

    kerning =
      for <<other::little-signed-16,
            amount::little-signed-16 <-
              binary_part(data, at + 16 + padding, pairs * 4)>>,
          into: %{},
          do: {other, amount}

    {character,
     %{source: {x, y, width, height}, advance: advance, offset: offset, kerning: kerning}}
  end
end
