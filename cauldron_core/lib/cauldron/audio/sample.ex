defmodule Cauldron.Audio.Sample do
  @moduledoc """
  Recorded sound a voice plays instead of an oscillator (a voice's `:sample`).

  Recorded audio, to be played as a `Cauldron.Audio.Voice`.

      kick = Sample.load!("kick.wav")
      part(bpm: 96, synth: Voice.new(sample: kick)) |> steps("x..x..x.")
  """

  @type t() :: TuningFork.Sample.t()

  @doc """
  The value at a fractional frame position in the recording, from -1.0 to 1.0.

  Cubic Hermite interpolation through the two frames either side and their neighbours. A
  position before the start or past the end is 0.0 rather than a wrap, unless the recording
  has a loop, which `looped/2` brings it back inside.
  """
  @spec at(t(), float()) :: float()
  def at(sample, position), do: TuningFork.Sample.at(sample, position)

  @doc """
  How long the recording lasts at its own speed, in seconds.
  """
  @spec duration(t()) :: float()
  def duration(sample), do: TuningFork.Sample.duration(sample)

  @doc """
  How long the recording lasts when played at `freq`, in seconds.

  Longer when pitched down and shorter when pitched up. A sample with no `:root`, or a `freq`
  of `nil`, gives `duration/1`.
  """
  @spec duration(t(), float() | nil) :: float()
  def duration(sample, freq), do: TuningFork.Sample.duration(sample, freq)

  @doc """
  How many frames long the recording is.
  """
  @spec frames(t()) :: non_neg_integer()
  def frames(sample), do: TuningFork.Sample.frames(sample)

  @doc """
  A sample from PCM already in memory.

  Stereo input is folded to mono, since a voice is synthesised in mono and panned afterwards.
  More than two channels raises `ArgumentError`.

  ## Options

    * `:rate` — samples per second of the PCM given, default 44100
    * `:channels` — 1 or 2, default 1
    * `:root` — the pitch the recording already is, as a note name or a frequency in Hz
    * `:loop` — `{from, to}` frames a voice goes round between once it reaches `to`, so a
      note can outlast the recording; default `nil`
    * `:gain` — a factor the recording is scaled by as it is loaded, default 1.0
    * `:name` — what to call it, default `"sample"`
  """
  @spec from_pcm(
          binary(),
          keyword()
        ) :: t()
  def from_pcm(pcm, opts \\ []), do: TuningFork.Sample.from_pcm(pcm, opts)

  @doc """
  Read a recording from disk: a WAV or a FLAC as they are, anything else (MP3, Ogg Vorbis)
  decoded first.

  Which it is comes from the file's own header, not its name. Raises if the file cannot be read
  or will not decode.

  ## Options

    * `:root` — the pitch the recording already is, as a note name or a frequency in Hz.
      Leave it out for percussion, which has no pitch to move from
    * `:name` — what to call it, default the file's basename

  `:rate` and `:channels` come from the file and are not taken here.
  """
  @spec load!(
          Path.t(),
          keyword()
        ) :: t()
  def load!(path, opts \\ []), do: TuningFork.Sample.load!(path, opts)

  @doc """
  `position` brought back inside the loop when the recording has one and the position has
  passed its end; unchanged otherwise.
  """
  @spec looped(t(), float()) :: float()
  def looped(sample, position), do: TuningFork.Sample.looped(sample, position)

  @doc """
  How far to move through the recording per output frame to sound at `freq` through a device
  running at `rate`.

  Two ratios in one: `freq` against the sample's `:root`, and the sample's own rate against
  `rate`. A sample with no `:root`, or a `freq` of `nil`, is read at its own pitch and still
  corrected for rate.
  """
  @spec ratio(t(), float() | nil, pos_integer()) :: float()
  def ratio(sample, freq, rate), do: TuningFork.Sample.ratio(sample, freq, rate)

  @doc """
  A new sample with the recording reversed, keeping its rate and root.
  """
  @spec reverse(t()) :: t()
  def reverse(sample), do: TuningFork.Sample.reverse(sample)

  @doc """
  A new sample cut out of this one: `length` seconds starting `from` seconds in.

  A range running past the end is truncated to what is there. The result keeps the rate and
  root of the original and gets its own `:id`, so caches tell it apart from what it came
  from.
  """
  @spec slice(t(), number(), number()) :: t()
  def slice(sample, from, length), do: TuningFork.Sample.slice(sample, from, length)
end
