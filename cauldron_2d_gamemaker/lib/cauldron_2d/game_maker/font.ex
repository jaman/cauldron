defmodule Cauldron2D.GameMaker.Font do
  @moduledoc """
  A font (a `FONT` entry): glyphs cut from one picture on a texture page.

  `picture` is the `Cauldron2D.GameMaker.Region` holding every glyph. Each glyph in
  `glyphs`, keyed by its character's code point, is a map of `source`
  `{x, y, width, height}` inside that picture, `advance` (pixels the pen moves after
  it), `offset` (pixels right of the pen it is drawn) and `kerning`, a map from the
  next character's code point to an extra advance. `size` is the point size it was
  made at, from the typeface `typeface`.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Region

  @enforce_keys [:name, :picture, :glyphs]
  defstruct [:name, :typeface, :size, :bold, :italic, :picture, :scale, glyphs: %{}]

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
          glyphs: %{non_neg_integer() => glyph()}
        }

  @doc "The font at `at`; `format` says where its glyph list sits."
  @spec read(binary(), non_neg_integer(), %{non_neg_integer() => Region.t()}, atom()) :: t()
  def read(data, at, regions, format) do
    <<_name::little-32, _typeface::little-32, size::binary-4, bold::little-32, italic::little-32,
      _range::binary-8, picture::little-32, scale_x::binary-4, scale_y::binary-4>> =
      binary_part(data, at, 40)

    %__MODULE__{
      name: Bytes.string_at(data, at),
      typeface: Bytes.string_at(data, at + 4),
      size: size(size),
      bold: bold != 0,
      italic: italic != 0,
      picture: Map.get(regions, picture),
      scale: {Bytes.float(scale_x), Bytes.float(scale_y)},
      glyphs: glyphs(data, at + glyphs_at(format))
    }
  end

  defp glyphs_at(:gms1), do: 40
  defp glyphs_at(_format), do: 44

  defp size(<<value::little-signed-32>>) when value >= 0, do: value
  defp size(bits), do: abs(Bytes.float(bits))

  defp glyphs(data, at) do
    data
    |> Bytes.pointers(at)
    |> Map.new(fn pointer -> glyph(data, pointer) end)
  end

  defp glyph(data, at) do
    <<character::little-16, x::little-16, y::little-16, width::little-16, height::little-16,
      advance::little-signed-16, offset::little-signed-16, pairs::little-16>> =
      binary_part(data, at, 16)

    kerning =
      for <<other::little-signed-16,
            amount::little-signed-16 <-
              binary_part(data, at + 16, pairs * 4)>>,
          into: %{},
          do: {other, amount}

    {character,
     %{source: {x, y, width, height}, advance: advance, offset: offset, kerning: kerning}}
  end
end
