defmodule Cauldron3D.Formats.Tga do
  @moduledoc """
  Truevision TGA pictures read into RGBA `Cauldron3D.Texture`s: colour-mapped,
  true-colour (24 or 32 bits) and greyscale, plain or run-length encoded, stored either
  way up.

      {:ok, texture} = Cauldron3D.Formats.Tga.parse(File.read!("gfx/env/desertup.tga"))
  """

  alias Cauldron3D.Texture

  @doc "The picture in `data`."
  @spec parse(binary()) :: {:ok, Texture.t()} | {:error, :not_a_tga}
  def parse(
        <<id_length, map_type, type, map_first::little-16, map_length::little-16, map_bits,
          _x::little-16, _y::little-16, width::little-16, height::little-16, bits, descriptor,
          rest::binary>>
      )
      when type in [1, 2, 3, 9, 10, 11] and width > 0 and height > 0 do
    map_bytes = if map_type == 1, do: map_length * div(map_bits + 7, 8), else: 0

    with <<_id::binary-size(^id_length), map::binary-size(^map_bytes), data::binary>> <- rest,
         {:ok, raw} <- unpack(data, type, width * height, div(bits + 7, 8)) do
      colours = colour_map(map, map_first, map_bits)

      pixels =
        for <<pixel::binary-size(div(^bits + 7, 8)) <- raw>>,
          into: <<>>,
          do: rgba(pixel, type, colours)

      top_down? = Bitwise.band(descriptor, 0x20) != 0

      {:ok,
       Texture.rgba(width, height, if(top_down?, do: pixels, else: flip(pixels, width, height)))}
    else
      _ -> {:error, :not_a_tga}
    end
  end

  def parse(_data), do: {:error, :not_a_tga}

  defp unpack(data, type, count, size) when type in [1, 2, 3] do
    if byte_size(data) >= count * size,
      do: {:ok, binary_part(data, 0, count * size)},
      else: :error
  end

  defp unpack(data, _type, count, size), do: runs(data, count, size, [])

  defp runs(_data, 0, _size, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp runs(<<header, rest::binary>>, left, size, acc) do
    length = min(Bitwise.band(header, 0x7F) + 1, left)

    if header >= 128 do
      case rest do
        <<pixel::binary-size(^size), rest::binary>> ->
          runs(rest, left - length, size, [:binary.copy(pixel, length) | acc])

        _ ->
          :error
      end
    else
      case rest do
        <<pixels::binary-size(^length * ^size), rest::binary>> ->
          runs(rest, left - length, size, [pixels | acc])

        _ ->
          :error
      end
    end
  end

  defp runs(_data, _left, _size, _acc), do: :error

  defp colour_map(<<>>, _first, _bits), do: nil

  defp colour_map(map, first, bits) do
    size = div(bits + 7, 8)
    entries = for <<entry::binary-size(^size) <- map>>, do: rgba(entry, 2, nil)
    {first, List.to_tuple(entries)}
  end

  defp rgba(<<index>>, type, {first, entries}) when type in [1, 9] do
    if index - first >= 0 and index - first < tuple_size(entries),
      do: elem(entries, index - first),
      else: <<0, 0, 0, 255>>
  end

  defp rgba(<<grey>>, _type, _colours), do: <<grey, grey, grey, 255>>
  defp rgba(<<grey, alpha>>, type, _colours) when type in [3, 11], do: <<grey, grey, grey, alpha>>

  defp rgba(<<low, high>>, _type, _colours) do
    value = high * 256 + low
    r = (Bitwise.band(Bitwise.bsr(value, 10), 31) * 255) |> div(31)
    g = (Bitwise.band(Bitwise.bsr(value, 5), 31) * 255) |> div(31)
    b = (Bitwise.band(value, 31) * 255) |> div(31)
    <<r, g, b, 255>>
  end

  defp rgba(<<b, g, r>>, _type, _colours), do: <<r, g, b, 255>>
  defp rgba(<<b, g, r, a>>, _type, _colours), do: <<r, g, b, a>>

  defp flip(pixels, width, height) do
    row = width * 4
    for y <- (height - 1)..0//-1, into: <<>>, do: binary_part(pixels, y * row, row)
  end
end
