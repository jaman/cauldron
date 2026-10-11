defmodule Cauldron2D.GameMaker.Wave do
  @moduledoc """
  A stored sound in WAVE form (a RIFF file of PCM samples), as games keep their short
  effects in the `AUDO` chunk.

      {:ok, %{rate: 44_100, channels: 1, pcm: pcm}} = Cauldron2D.GameMaker.Wave.read(bytes)

  `pcm` is signed 16-bit little-endian samples, channels interleaved, whatever the file
  stored: 8-bit samples are widened, 24- and 32-bit samples keep their top 16 bits.
  A file in the extensible format is read when its sub-format is PCM. Anything that is
  not uncompressed PCM is `{:error, :not_pcm}`; a file that is not
  WAVE is `{:error, :not_wave}`.
  """

  @doc "The rate, channel count and 16-bit PCM of the WAVE file in `bytes`."
  @spec read(binary()) ::
          {:ok, %{rate: pos_integer(), channels: pos_integer(), pcm: binary()}}
          | {:error, :not_wave | :not_pcm}
  def read(<<"RIFF", _size::little-32, "WAVE", chunks::binary>>) do
    with {:ok, format} <- chunk(chunks, "fmt "),
         {:ok, data} <- chunk(chunks, "data"),
         <<tag::little-16, channels::little-16, rate::little-32, _byte_rate::little-32,
           _align::little-16, bits::little-16, extension::binary>> <- format,
         true <- pcm?(tag, extension) and bits in [8, 16, 24, 32] do
      {:ok, %{rate: rate, channels: channels, pcm: widen(data, bits)}}
    else
      {:error, :missing} -> {:error, :not_wave}
      _other -> {:error, :not_pcm}
    end
  end

  def read(_bytes), do: {:error, :not_wave}

  defp pcm?(1, _extension), do: true

  defp pcm?(
         0xFFFE,
         <<_size::little-16, _valid::little-16, _mask::little-32, 1::little-16, _::binary>>
       ),
       do: true

  defp pcm?(_tag, _extension), do: false

  defp chunk(<<id::binary-4, size::little-32, rest::binary>>, id) when byte_size(rest) >= size,
    do: {:ok, binary_part(rest, 0, size)}

  defp chunk(<<_id::binary-4, size::little-32, rest::binary>>, wanted) do
    skip = size + rem(size, 2)

    if byte_size(rest) >= skip,
      do: chunk(binary_part(rest, skip, byte_size(rest) - skip), wanted),
      else: {:error, :missing}
  end

  defp chunk(_bytes, _wanted), do: {:error, :missing}

  defp widen(data, 16), do: binary_part(data, 0, byte_size(data) - rem(byte_size(data), 2))

  defp widen(data, 8),
    do: for(<<sample <- data>>, into: <<>>, do: <<(sample - 128) * 256::little-signed-16>>)

  defp widen(data, 24),
    do: for(<<_low, top::little-signed-16 <- data>>, into: <<>>, do: <<top::little-signed-16>>)

  defp widen(data, 32),
    do:
      for(<<_low::16, top::little-signed-16 <- data>>, into: <<>>, do: <<top::little-signed-16>>)
end
