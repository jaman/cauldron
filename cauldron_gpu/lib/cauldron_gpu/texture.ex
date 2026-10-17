defmodule CauldronGPU.Texture do
  @moduledoc """
  A picture to upload. `pixels` is `width * height` pixels, rows from the top: four bytes
  RGBA for `:srgb` (colour pictures) and `:linear` (data such as roughness), eight bytes
  (four little-endian half floats) for `:rgba16f`.

      CauldronGPU.Texture.checker(64, 8, {255, 255, 255, 255}, {40, 40, 40, 255})
  """

  @type format :: :srgb | :linear | :rgba16f
  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          pixels: binary(),
          format: format(),
          filter: :nearest | :linear,
          wrap: :repeat | :clamp,
          mipmaps: boolean()
        }

  @enforce_keys [:width, :height, :pixels]
  defstruct [
    :width,
    :height,
    :pixels,
    format: :srgb,
    filter: :linear,
    wrap: :repeat,
    mipmaps: true
  ]

  @doc "A `size`×`size` checkerboard of `squares` squares a side, in two RGBA colours."
  @spec checker(pos_integer(), pos_integer(), tuple(), tuple(), keyword()) :: t()
  def checker(size, squares, {r1, g1, b1, a1}, {r2, g2, b2, a2}, fields \\ []) do
    square = max(div(size, squares), 1)

    pixels =
      for y <- 0..(size - 1), x <- 0..(size - 1), into: <<>> do
        if rem(div(x, square) + div(y, square), 2) == 0,
          do: <<r1, g1, b1, a1>>,
          else: <<r2, g2, b2, a2>>
      end

    struct!(__MODULE__, [width: size, height: size, pixels: pixels] ++ fields)
  end
end
