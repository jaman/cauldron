defmodule Cauldron2D.Mask do
  @moduledoc """
  Which pixels of a picture are solid, one bit each.

  `bits` holds `height` rows, each padded to whole bytes, the leftmost pixel of a byte
  in its high bit.

      mask = Cauldron2D.Mask.from_raster(raster)
      Cauldron2D.Mask.set?(mask, {3, 7})
  """

  alias FrenchCurve.Raster

  @enforce_keys [:width, :height, :bits]
  defstruct [:width, :height, :bits]

  @type t :: %__MODULE__{width: pos_integer(), height: pos_integer(), bits: binary()}

  @doc "A mask from rows of bits as described above."
  @spec new(pos_integer(), pos_integer(), binary()) :: t()
  def new(width, height, bits) when byte_size(bits) == div(width + 7, 8) * height,
    do: %__MODULE__{width: width, height: height, bits: bits}

  @doc "The mask of `raster`'s pixels whose alpha is at least `threshold` (default 1)."
  @spec from_raster(Raster.t(), 1..255) :: t()
  def from_raster(%Raster{} = raster, threshold \\ 1) do
    {width, height} = Raster.dimensions(raster)
    rgba = Raster.to_rgba_binary(raster)
    padding = div(width + 7, 8) * 8 - width

    bits =
      for row <- 0..(height - 1), into: <<>> do
        line = binary_part(rgba, row * width * 4, width * 4)
        solid = for <<_r, _g, _b, alpha <- line>>, into: <<>>, do: <<bool(alpha >= threshold)::1>>
        <<solid::bitstring, 0::size(padding)>>
      end

    new(width, height, bits)
  end

  @doc "Whether pixel `{x, y}` is solid; pixels outside the mask are not."
  @spec set?(t(), {integer(), integer()}) :: boolean()
  def set?(%__MODULE__{width: width, height: height, bits: bits}, {x, y})
      when x >= 0 and y >= 0 and x < width and y < height do
    byte = :binary.at(bits, y * div(width + 7, 8) + div(x, 8))
    Bitwise.band(byte, Bitwise.bsr(0x80, rem(x, 8))) != 0
  end

  def set?(%__MODULE__{}, _point), do: false

  defp bool(true), do: 1
  defp bool(false), do: 0
end
