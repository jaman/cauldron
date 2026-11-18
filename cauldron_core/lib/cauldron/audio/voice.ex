defmodule Cauldron.Audio.Voice do
  @moduledoc """
  A sound a game plays for an event: one or more oscillators or noise through an envelope, as `c:Cauldron.Client.Game.sounds/0` gives them.

  One sound described as a waveform, pitch, envelope and filter, rendered to 16-bit PCM.

      Cauldron.Audio.Voice.new(shape: :saw, freq: 220.0) |> Cauldron.Audio.Voice.render(44_100)
  """

  @type t() :: TuningFork.Voice.t()

  @doc """
  Hold each sample for `every` samples, carrying the hold in `extra`. `nil` or 1 changes
  nothing.
  """
  @spec coarsened(float(), number() | nil, map()) :: {float(), map()}
  def coarsened(sample, every, extra), do: TuningFork.Voice.coarsened(sample, every, extra)

  @doc """
  Round the sample to `bits` of resolution. `nil` or 16 and up leaves it alone; `bits` may be
  fractional.

      iex> Cauldron.Audio.Voice.crush(0.3, nil)
      0.3
      iex> Cauldron.Audio.Voice.crush(0.3, 1) in [-1.0, 0.0, 1.0]
      true
  """
  @spec crush(float(), number() | nil) :: float()
  def crush(sample, bits), do: TuningFork.Voice.crush(sample, bits)

  @doc """
  Drive the sample through a soft clipper, `amount` deciding how hard. `nil` or 0.0 leaves
  it alone; the gain is normalised out afterwards.

      iex> Cauldron.Audio.Voice.distort(0.5, 0.0)
      0.5
      iex> Cauldron.Audio.Voice.distort(0.5, 4.0) > 0.5
      true
  """
  @spec distort(float(), number() | nil) :: float()
  def distort(sample, amount), do: TuningFork.Voice.distort(sample, amount)

  @doc """
  How long the voice sounds for, in seconds: the length of its envelope.
  """
  @spec duration(t()) :: float()
  def duration(voice), do: TuningFork.Voice.duration(voice)

  @doc """
  The curves actually moving on this voice, as `%{freq:, cutoff:, gain:}`.

  A field whose curve holds one value is `nil` here, and so is `:freq` where `:sweep` is 1.0
  and no freq curve is given.
  """
  @spec modulation(t()) :: %{
          freq: Cauldron.Audio.Curve.t() | nil,
          cutoff: Cauldron.Audio.Curve.t() | nil,
          gain: Cauldron.Audio.Curve.t() | nil
        }
  def modulation(voice), do: TuningFork.Voice.modulation(voice)

  @doc """
  A voice, with anything unset left at its default. An unknown key raises `KeyError`.

  ## Options

    * `:shape` — `:sine`, `:square`, `:saw`, `:triangle` or `:noise`, default `:sine`
    * `:freq` — starting pitch in Hz, default 440.0. Ignored by `:noise`
    * `:sweep` — pitch multiplier reached by the end of the envelope, default 1.0. A `:freq`
      curve supersedes it, even a flat one
    * `:envelope` — a `Cauldron.Audio.Envelope`. When `nil`, a voice with a `:sample` gets one
      spanning the recording at the voice's pitch with a 2 ms attack and 4 ms release, and
      any other voice gets `Cauldron.Audio.Envelope.new/1`'s defaults
    * `:gain` — 0.0 to 1.0, default 0.8
    * `:pan` — `-1.0` hard left to `1.0` hard right, default `0.0`
    * `:filter` — a `Cauldron.Audio.Filter`, or `nil` for none
    * `:cutoff` — one-pole lowpass coefficient, 0.0 to 1.0; `nil` for none
    * `:highpass` — one-pole highpass coefficient, 0.0 to 1.0; `nil` for none
    * `:crush` — round every sample to this many bits; `nil` or 16 for none
    * `:distort` — drive into a soft clipper, 0.0 upwards; `nil` for none
    * `:waveshape` — Strudel's `shape` waveshaper, 0.0 to below 1.0; `nil` for none
    * `:vowel` — `:a`, `:e`, `:i`, `:o` or `:u`; `nil` for none
    * `:fm`, `:fmh`, `:fmattack` — modulation index of a second oscillator, its frequency as
      a multiple of `:freq`, and the fraction of the note over which the index arrives
    * `:vib`, `:vibmod` — vibrato rate in hertz and depth in semitones
    * `:coarse` — hold every sample for this many; `nil` or 1 for none
    * `:phaser`, `:phaserdepth` — sweep rate in hertz and depth 0.0 to 1.0
    * `:curves` — `%{freq: curve, cutoff: curve, gain: curve}` of `Cauldron.Audio.Curve`s, each a
      multiplier over its field across the note
    * `:sample` — a `Cauldron.Audio.Sample` to play instead of an oscillator, or `nil`
    * `:seed` — the noise seed; the same seed renders the same samples
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: TuningFork.Voice.new(opts)

  @doc """
  Render to mono signed 16-bit little-endian PCM at `rate` samples per second.

  The result is `duration/1` seconds long, and at least one frame. `:pan` is not applied.
  """
  @spec render(t(), pos_integer()) :: binary()
  def render(voice, rate), do: TuningFork.Voice.render(voice, rate)

  @doc """
  Render for `channels` channels: 2 applies the voice's `:pan`, 1 is `render/2` unchanged.
  """
  @spec render(t(), pos_integer(), pos_integer()) :: binary()
  def render(voice, rate, channels), do: TuningFork.Voice.render(voice, rate, channels)

  @doc """
  Bend a sample over 0.7 softly towards full scale instead of clipping it. Samples within
  -0.7 to 0.7 are unchanged.

      iex> Cauldron.Audio.Voice.saturate(0.5)
      0.5
      iex> Cauldron.Audio.Voice.saturate(4.0) < 1.0
      true
  """
  @spec saturate(float()) :: float()
  def saturate(sample), do: TuningFork.Voice.saturate(sample)

  @doc """
  The vowels `:vowel` takes, each with its three formants as `{hz, level}` pairs.

      iex> Cauldron.Audio.Voice.vowels() |> Keyword.keys()
      [:a, :e, :i, :o, :u]
  """
  @spec vowels() :: keyword([{float(), float()}])
  def vowels, do: TuningFork.Voice.vowels()

  @doc """
  Bend the sample by Strudel's `shape` curve, `amount` from 0.0 (none) towards 1.0 (hard).
  `nil` or 0.0 leaves it alone; 1.0 and above is treated as just under 1.0.

      iex> Cauldron.Audio.Voice.waveshape(0.5, 0.0)
      0.5
  """
  @spec waveshape(float(), number() | nil) :: float()
  def waveshape(sample, amount), do: TuningFork.Voice.waveshape(sample, amount)
end
