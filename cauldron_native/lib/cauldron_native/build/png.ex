defmodule CauldronNative.Build.Png do
  @moduledoc """
  What the stores require of an app's images, read from a PNG's header: its size and
  whether it has an alpha channel. An App Store icon is 1024 × 1024 with no alpha.
  `solid!/4` writes a PNG of one colour.
  """

  @type info :: %{width: pos_integer(), height: pos_integer(), alpha?: boolean()}

  @doc "The size of the PNG at `path` and whether it has alpha; raises when it is not a PNG."
  @spec info!(String.t()) :: info()
  def info!(path) do
    case File.read!(path) do
      <<137, "PNG", 13, 10, 26, 10, _length::32, "IHDR", width::32, height::32, _depth, colour,
        _rest::binary>> = png ->
        %{width: width, height: height, alpha?: colour in [4, 6] or transparency?(png)}

      _other ->
        Mix.raise("#{path} is not a PNG")
    end
  end

  @doc "Raise unless the PNG at `path` can be the App Store icon: 1024 × 1024 without alpha."
  @spec icon!(String.t()) :: String.t()
  def icon!(path) do
    case info!(path) do
      %{width: 1024, height: 1024, alpha?: false} ->
        path

      %{width: 1024, height: 1024} ->
        Mix.raise(
          "The icon #{path} has an alpha channel; the App Store takes an icon without one"
        )

      %{width: width, height: height} ->
        Mix.raise("The icon #{path} is #{width} × #{height}; it must be 1024 × 1024")
    end
  end

  @doc "Write a `width` × `height` PNG at `path` of the one colour `{r, g, b}`."
  @spec solid!(String.t(), pos_integer(), pos_integer(), {byte(), byte(), byte()}) :: :ok
  def solid!(path, width, height, {red, green, blue}) do
    row = <<0>> <> :binary.copy(<<red, green, blue>>, width)
    header = <<width::32, height::32, 8, 2, 0, 0, 0>>

    File.write!(path, [
      <<137, "PNG", 13, 10, 26, 10>>,
      chunk("IHDR", header),
      chunk("IDAT", :zlib.compress(:binary.copy(row, height))),
      chunk("IEND", "")
    ])
  end

  defp chunk(type, data),
    do: [<<byte_size(data)::32>>, type, data, <<:erlang.crc32(type <> data)::32>>]

  defp transparency?(<<_signature::binary-size(8), chunks::binary>>), do: chunk?(chunks, "tRNS")

  defp chunk?(<<_length::32, name::binary-size(4), _rest::binary>>, name), do: true
  defp chunk?(<<_length::32, "IDAT", _rest::binary>>, _name), do: false

  defp chunk?(
         <<length::32, _name::binary-size(4), _data::binary-size(length), _crc::32,
           rest::binary>>,
         name
       ),
       do: chunk?(rest, name)

  defp chunk?(_end, _name), do: false
end
