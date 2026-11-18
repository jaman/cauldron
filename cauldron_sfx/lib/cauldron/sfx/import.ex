defmodule Cauldron.SFX.Import do
  @moduledoc """
  Turns a recording into a bank's sound effects: the WAV is cut into sounds,
  each sound normalised, written beside the bank and listed as a variant of
  one event.

      {:ok, bank} =
        Cauldron.SFX.Import.add("woodpecker.wav", "priv/sfx/sfx.json", event: "woodpecker")

  A recording is cut at silence by default — a gap of `:gap_ms` below
  `:silence_db` — or into `:slices` equal parts. Each cut's peak is moved to
  `:peak_db` (a gain change, not a compressor, so the dynamics stay), and it
  is written as `<event>-<n>.wav` in the bank's directory and listed as a
  `{"kind": "sample", "file": …}` variant. Several cuts of one sound make one
  event whose variants are picked between, so a repeated sound does not
  sound repeated.

  Only 16-bit PCM WAVs are read and written, as `Cauldron.Audio.Recording`
  reads them.
  """

  alias Cauldron.Audio.Recording
  alias Cauldron.SFX

  @bytes_per_sample 2
  @full_scale 32_767

  @options [
    event: nil,
    slices: nil,
    silence_db: -50.0,
    gap_ms: 120,
    pad_ms: 10,
    peak_db: -1.0,
    gain: 0.8
  ]

  @doc """
  Adds the sounds of `wav` to the bank at `bank` (a directory or a `sfx.json`
  file, created when missing) and writes it.

  ## Options

    * `:event` - the event the cuts become variants of. Default: the WAV's
      file name
    * `:slices` - how many equal parts to cut, instead of cutting at silence
    * `:silence_db` - what counts as silence, in dBFS. Defaults to `-50.0`
    * `:gap_ms` - how long a silence cuts. Defaults to `120`
    * `:pad_ms` - how much of the silence either side of a cut to keep.
      Defaults to `10`
    * `:peak_db` - the level each cut is normalised to, in dBFS. Defaults
      to `-1.0`
    * `:gain` - the variants' gain in the bank. Defaults to `0.8`
  """
  @spec add(Path.t(), Path.t(), keyword()) :: {:ok, SFX.t()} | {:error, term() | String.t()}
  def add(wav, bank_path, opts \\ []) do
    opts = Keyword.validate!(opts, @options)

    with {:ok, %{rate: rate, channels: channels, pcm: pcm}} <- Recording.read(wav),
         :ok <- supported(rate, channels) do
      event = opts[:event] || file_event(wav)
      add_cuts(cuts(pcm, rate, channels, opts), rate, channels, bank_path, event, opts)
    end
  end

  defp add_cuts(cuts, rate, channels, bank_path, event, opts) do
    directory = bank_path |> SFX.manifest() |> Path.dirname()

    written =
      cuts
      |> Enum.with_index(1)
      |> Enum.map(fn {pcm, index} ->
        file = "#{event}-#{index}.wav"

        %{
          file: file,
          pcm: pcm,
          rate: rate,
          channels: channels,
          variant: %{"kind" => "sample", "file" => file, "gain" => opts[:gain], "pan" => 0.0}
        }
      end)

    bank =
      SFX.put_event(read_bank(bank_path), event, %{variants: Enum.map(written, & &1.variant)})

    with :ok <- write_all(written, directory),
         :ok <- SFX.write(bank, bank_path) do
      {:ok, bank}
    end
  end

  defp write_all(variants, directory) do
    Enum.reduce_while(variants, :ok, fn variant, :ok ->
      case write_wav(Path.join(directory, variant.file), variant) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp write_wav(path, %{rate: rate, channels: channels, pcm: pcm}) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, wave(rate, channels, pcm))
    end
  end

  @doc """
  The 16-bit PCM WAV file of `pcm`, `channels` channels at `rate`.
  """
  @spec wave(pos_integer(), pos_integer(), binary()) :: binary()
  def wave(rate, channels, pcm) do
    size = byte_size(pcm)
    block_align = channels * @bytes_per_sample

    "RIFF" <>
      <<36 + size::little-32>> <>
      "WAVE" <>
      "fmt " <>
      <<16::little-32, 1::little-16, channels::little-16, rate::little-32,
        rate * block_align::little-32, block_align::little-16, 16::little-16>> <>
      "data" <> <<size::little-32>> <> pcm
  end

  defp read_bank(bank) do
    case SFX.read(bank) do
      {:ok, bank} -> bank
      {:error, _reason} -> SFX.new()
    end
  end

  defp supported(rate, channels) when rate > 0 and channels in [1, 2], do: :ok

  defp supported(_rate, _channels),
    do: {:error, "only mono and stereo recordings can be imported"}

  defp cuts(pcm, rate, channels, opts) do
    frame_bytes = channels * @bytes_per_sample

    segments =
      case opts[:slices] do
        nil -> at_silence(pcm, rate, channels, opts)
        count when count > 0 -> equal_parts(pcm, frame_bytes, count)
      end

    Enum.map(segments, &normalise(&1, opts[:peak_db]))
  end

  defp equal_parts(pcm, frame_bytes, count) do
    frames = div(byte_size(pcm), frame_bytes)
    part = div(frames, count)

    if part == 0 do
      [pcm]
    else
      # The last part takes whatever the division left over, so no frame is dropped.
      for index <- 0..(count - 1) do
        start = index * part
        length = min(part, frames - start)
        binary_part(pcm, start * frame_bytes, length * frame_bytes)
      end
    end
  end

  defp at_silence(pcm, rate, channels, opts) do
    frame_bytes = channels * @bytes_per_sample
    threshold = round(@full_scale * :math.pow(10, opts[:silence_db] / 20))
    gap = div(opts[:gap_ms] * rate, 1000)
    pad = div(opts[:pad_ms] * rate, 1000)
    frames_total = div(byte_size(pcm), frame_bytes)

    loud =
      pcm
      |> frames(frame_bytes)
      |> Enum.with_index()
      |> Enum.filter(fn {frame, _index} -> peak(frame) >= threshold end)
      |> Enum.map(&elem(&1, 1))

    case groups(loud, gap) do
      [] ->
        [pcm]

      groups ->
        Enum.map(groups, fn {first, last} ->
          from = max(first - pad, 0)
          to = min(last + pad + 1, frames_total)
          binary_part(pcm, from * frame_bytes, (to - from) * frame_bytes)
        end)
    end
  end

  defp frames(pcm, frame_bytes), do: frames(pcm, frame_bytes, [])

  defp frames(<<>>, _frame_bytes, acc), do: Enum.reverse(acc)

  defp frames(pcm, frame_bytes, acc) do
    <<frame::binary-size(^frame_bytes), rest::binary>> = pcm
    frames(rest, frame_bytes, [frame | acc])
  end

  defp groups([], _gap), do: []

  defp groups([first | rest], gap) do
    {groups, current} =
      Enum.reduce(rest, {[], {first, first}}, fn index, {groups, {start, last}} ->
        if index - last <= gap,
          do: {groups, {start, index}},
          else: {[{start, last} | groups], {index, index}}
      end)

    Enum.reverse([current | groups])
  end

  defp peak(frame) do
    frame
    |> samples()
    |> Enum.map(&abs/1)
    |> Enum.max(fn -> 0 end)
  end

  defp samples(frame) do
    for <<sample::little-signed-16 <- frame>>, do: sample
  end

  defp normalise(pcm, peak_db) do
    case peak(pcm) do
      0 ->
        pcm

      peak ->
        scale(pcm, @full_scale * :math.pow(10, peak_db / 20) / peak)
    end
  end

  defp scale(pcm, factor) do
    for <<sample::little-signed-16 <- pcm>>, into: <<>> do
      <<round(sample * factor)::little-signed-16>>
    end
  end

  defp file_event(wav) do
    wav
    |> Path.basename(Path.extname(wav))
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
