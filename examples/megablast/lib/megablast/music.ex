defmodule Megablast.Music do
  @moduledoc """
  The demo's soundtrack: one rendered loop in `priv/audio/megablast.wav`, read as PCM.

  `piece/0` reads the file the first time it is asked and keeps it, so `cue/0` costs
  nothing and may be asked on every frame. Both answer `nil` where the recording is not
  there, and the demo then plays silent.
  """

  @name "megablast"
  @bpm 118
  @kept {__MODULE__, :piece}

  @doc "The piece's name."
  @spec name() :: String.t()
  def name, do: @name

  @doc "The piece, or `nil` where its recording is missing."
  @spec piece() :: {String.t(), map()} | nil
  def piece do
    case :persistent_term.get(@kept, :unread) do
      :unread ->
        piece = read()
        :persistent_term.put(@kept, piece)
        piece

      piece ->
        piece
    end
  end

  @doc "The cue for the piece, or `nil` where there is none."
  @spec cue() :: map() | nil
  def cue do
    case piece() do
      nil -> nil
      {name, _spec} -> %{piece: name, section: :run, layers: %{track: 1.0}}
    end
  end

  @doc "Forget the recording, so the next `piece/0` reads it again."
  @spec forget() :: :ok
  def forget do
    :persistent_term.erase(@kept)
    :ok
  end

  defp read do
    path = Path.join([:code.priv_dir(:megablast), "audio", "#{@name}.wav"])

    with {:ok, %File.Stat{size: size, mtime: mtime}} <- File.stat(path),
         {:ok, bytes} <- File.read(path),
         samples when is_binary(samples) <- data_chunk(bytes) do
      {@name,
       %{
         bpm: @bpm,
         beats_per_bar: 4,
         layers: [:track],
         sections: %{run: %{track: {:pcm, samples}}},
         fingerprint: "#{size}-#{:erlang.phash2(mtime)}"
       }}
    else
      _missing -> nil
    end
  end

  defp data_chunk(<<"RIFF", _size::little-32, "WAVE", chunks::binary>>), do: chunk(chunks)
  defp data_chunk(_bytes), do: nil

  defp chunk(<<"data", size::little-32, rest::binary>>) when byte_size(rest) >= size,
    do: binary_part(rest, 0, size)

  defp chunk(<<_id::binary-size(4), size::little-32, rest::binary>>)
       when byte_size(rest) >= size do
    padded = size + rem(size, 2)

    case rest do
      <<_skipped::binary-size(^padded), more::binary>> -> chunk(more)
      _short -> nil
    end
  end

  defp chunk(_bytes), do: nil
end
