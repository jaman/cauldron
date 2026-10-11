defmodule Cauldron3D.Formats.Bmp do
  @moduledoc """
  Windows bitmap pictures, uncompressed 8-bit (with their palette) or 24- and 32-bit,
  read into `Cauldron3D.Texture`s: an 8-bit picture as an indexed texture with its own
  palette, the others as RGBA.

      {:ok, texture} = Cauldron3D.Formats.Bmp.parse(File.read!("gfx/env/desertup.bmp"))
  """

  alias Cauldron3D.Texture

  @doc "The picture in `data`."
  @spec parse(binary()) :: {:ok, Texture.t()} | {:error, :not_a_bmp}
  def parse(
        <<"BM", _size::little-32, _reserved::little-32, offset::little-32, header::little-32,
          width::little-signed-32, height::little-signed-32, _planes::little-16, bits::little-16,
          0::little-32, _rest::binary>> = data
      )
      when bits in [8, 24, 32] and width > 0 and height != 0 do
    rows = abs(height)
    stride = div(width * bits + 31, 32) * 4

    if offset + stride * rows <= byte_size(data) do
      lines =
        for y <- 0..(rows - 1), do: binary_part(data, offset + y * stride, div(width * bits, 8))

      lines = if height > 0, do: Enum.reverse(lines), else: lines
      {:ok, texture(bits, width, rows, IO.iodata_to_binary(lines), data, 14 + header)}
    else
      {:error, :not_a_bmp}
    end
  end

  def parse(_data), do: {:error, :not_a_bmp}

  defp texture(8, width, height, pixels, data, palette_at) do
    palette =
      for <<b, g, r,
            _ <- binary_part(data, palette_at, min(1024, byte_size(data) - palette_at))>>,
          into: <<>>,
          do: <<r, g, b>>

    Texture.new(width, height, pixels, palette <> :binary.copy(<<0>>, 768 - byte_size(palette)))
  end

  defp texture(24, width, height, pixels, _data, _palette_at),
    do: Texture.rgba(width, height, for(<<b, g, r <- pixels>>, into: <<>>, do: <<r, g, b, 255>>))

  defp texture(32, width, height, pixels, _data, _palette_at),
    do:
      Texture.rgba(width, height, for(<<b, g, r, _ <- pixels>>, into: <<>>, do: <<r, g, b, 255>>))
end
