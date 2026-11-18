defmodule Cauldron.Audio.Recording do
  @moduledoc """
  Recordings read from WAV files, in the shape `Cauldron.Audio` plays them:
  `%{rate: rate, channels: channels, pcm: pcm}`, the samples signed 16-bit
  little-endian, interleaved.

      {:ok, song} = Cauldron.Audio.Recording.read("priv/audio/title.wav")
      {:pcm, song.pcm, song.rate, song.channels}

  Only uncompressed 16-bit PCM is read.
  """

  @type t :: %{rate: pos_integer(), channels: pos_integer(), pcm: binary()}

  @doc """
  The recording in the WAV file at `path`. Fails with `{:error, :enoent}` and the other
  `File.read/1` reasons, `{:error, :not_wav}` for a file that is not RIFF WAVE, and
  `{:error, :unsupported}` for one that is not 16-bit PCM or has no data.
  """
  @spec read(Path.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    with {:ok, bytes} <- File.read(path), do: parse(bytes)
  end

  @doc "The recording in WAV `bytes`; fails as `read/1` does."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_wav | :unsupported}
  def parse(<<"RIFF", _size::little-32, "WAVE", chunks::binary>>), do: chunks(chunks, %{})
  def parse(_bytes), do: {:error, :not_wav}

  defp chunks(
         <<"fmt ", size::little-32, 1::little-16, channels::little-16, rate::little-32,
           _byte_rate::little-32, _align::little-16, 16::little-16, rest::binary>>,
         found
       )
       when size >= 16 do
    skip = size - 16 + rem(size, 2)

    case rest do
      <<_extra::binary-size(^skip), more::binary>> ->
        chunks(more, Map.merge(found, %{rate: rate, channels: channels}))

      _short ->
        {:error, :unsupported}
    end
  end

  defp chunks(<<"data", size::little-32, rest::binary>>, %{rate: _, channels: _} = found)
       when byte_size(rest) >= size,
       do: {:ok, Map.put(found, :pcm, binary_part(rest, 0, size))}

  defp chunks(<<_id::binary-size(4), size::little-32, rest::binary>>, found)
       when byte_size(rest) >= size + rem(size, 2) do
    padded = size + rem(size, 2)
    <<_skipped::binary-size(^padded), more::binary>> = rest
    chunks(more, found)
  end

  defp chunks(_bytes, _found), do: {:error, :unsupported}
end
