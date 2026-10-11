defmodule Cauldron3D.Texture do
  @moduledoc """
  A picture, rows top to bottom: indexed colour, one byte per pixel and optionally its
  own palette, or RGBA, four bytes per pixel.

      Cauldron3D.Texture.new(64, 64, pixels)
      Cauldron3D.Texture.new(64, 64, pixels, palette)
      Cauldron3D.Texture.rgba(64, 64, rgba_pixels)
      Cauldron3D.Texture.at(texture, 3, 7)

  `palette` is 768 bytes of red, green and blue, or `nil` for an indexed texture whose
  indices are into the palette of whatever it is drawn on; `colours` is that palette as a
  tuple of 256 RGBA binaries. An RGBA texture's alpha is 0 where it is see-through.
  """

  @enforce_keys [:width, :height, :pixels]
  defstruct [:width, :height, :pixels, palette: nil, colours: nil, format: :indexed]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          pixels: binary(),
          palette: binary() | nil,
          colours: tuple() | nil,
          format: :indexed | :rgba
        }

  @doc "An indexed texture of `width` by `height` from its pixels. Raises `ArgumentError` when the sizes disagree."
  @spec new(pos_integer(), pos_integer(), binary()) :: t()
  def new(width, height, pixels)
      when width > 0 and height > 0 and byte_size(pixels) == width * height,
      do: %__MODULE__{width: width, height: height, pixels: pixels}

  def new(width, height, pixels),
    do:
      raise(
        ArgumentError,
        "a #{width}x#{height} texture takes #{width * height} bytes, not #{byte_size(pixels)}"
      )

  @doc "An indexed texture of `width` by `height` from its pixels and its own 768-byte `palette`."
  @spec new(pos_integer(), pos_integer(), binary(), binary()) :: t()
  def new(width, height, pixels, palette) when byte_size(palette) == 768,
    do: %{new(width, height, pixels) | palette: palette, colours: colours(palette)}

  @doc "An RGBA texture of `width` by `height`. Raises `ArgumentError` when the sizes disagree."
  @spec rgba(pos_integer(), pos_integer(), binary()) :: t()
  def rgba(width, height, pixels)
      when width > 0 and height > 0 and byte_size(pixels) == width * height * 4,
      do: %__MODULE__{width: width, height: height, pixels: pixels, format: :rgba}

  def rgba(width, height, pixels),
    do:
      raise(
        ArgumentError,
        "a #{width}x#{height} RGBA texture takes #{width * height * 4} bytes, not #{byte_size(pixels)}"
      )

  @doc "A 768-byte palette as a tuple of 256 opaque RGBA binaries."
  @spec colours(binary()) :: tuple()
  def colours(palette), do: List.to_tuple(for(<<r, g, b <- palette>>, do: <<r, g, b, 255>>))

  @doc "The colour index at `{x, y}` of an indexed texture, wrapping both ways."
  @spec at(t(), integer(), integer()) :: byte()
  def at(%__MODULE__{width: width, height: height, pixels: pixels}, x, y),
    do: :binary.at(pixels, Integer.mod(y, height) * width + Integer.mod(x, width))

  @doc "The texture with `left` columns from its left edge, as two textures `{left, rest}`."
  @spec split(t(), pos_integer()) :: {t(), t()}
  def split(%__MODULE__{width: width, height: height, pixels: pixels} = texture, left)
      when left < width do
    rows = for row <- 0..(height - 1), do: binary_part(pixels, row * width, width)
    lefts = for row <- rows, into: <<>>, do: binary_part(row, 0, left)
    rights = for row <- rows, into: <<>>, do: binary_part(row, left, width - left)

    {%{new(left, height, lefts) | palette: texture.palette, colours: texture.colours},
     %{new(width - left, height, rights) | palette: texture.palette, colours: texture.colours}}
  end
end
