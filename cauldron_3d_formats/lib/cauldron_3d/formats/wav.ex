defmodule Cauldron3D.Formats.Wav do
  @moduledoc """
  RIFF WAVE sounds of 8- or 16-bit mono PCM, read to 16-bit PCM.

      {:ok, %{rate: rate, pcm: pcm, loop: loop}} = Cauldron3D.Formats.Wav.read(bytes)

  A file with a cue point loops from it; `loop` says where, in seconds.
  """

  @doc "The sound's rate, 16-bit PCM and loop start in seconds (`nil` for a sound that plays once)."
  @spec read(binary() | nil) ::
          {:ok, %{rate: pos_integer(), pcm: binary(), loop: float() | nil}} | :error
  def read(<<"RIFF", _size::little-32, "WAVE", chunks::binary>>) do
    found = chunks(chunks, %{})

    case found do
      %{
        "fmt " =>
          <<1::little-16, 1::little-16, rate::little-32, _::little-32, _::little-16,
            bits::little-16, _::binary>>,
        "data" => data
      } ->
        {:ok, %{rate: rate, pcm: pcm(data, bits), loop: loop(found, rate)}}

      _ ->
        :error
    end
  end

  def read(_data), do: :error

  defp chunks(<<id::binary-4, size::little-32, rest::binary>>, acc)
       when byte_size(rest) >= size do
    <<body::binary-size(^size), rest::binary>> = rest

    rest =
      if rem(size, 2) == 1 and byte_size(rest) > 0,
        do: binary_part(rest, 1, byte_size(rest) - 1),
        else: rest

    chunks(rest, Map.put_new(acc, id, body))
  end

  defp chunks(<<id::binary-4, _size::little-32, rest::binary>>, acc),
    do: Map.put_new(acc, id, rest)

  defp chunks(_rest, acc), do: acc

  defp pcm(data, 8),
    do: for(<<byte <- data>>, into: <<>>, do: <<(byte - 128) * 256::16-signed-little>>)

  defp pcm(data, 16), do: binary_part(data, 0, div(byte_size(data), 2) * 2)
  defp pcm(_data, _bits), do: <<>>

  defp loop(
         %{"cue " => <<count::little-32, _id::little-32, position::little-32, _::binary>>},
         rate
       )
       when count > 0,
       do: position / rate

  defp loop(_chunks, _rate), do: nil
end
