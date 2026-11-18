defmodule Cauldron.Audio.Score do
  @moduledoc """
  A piece of music: parts placed in time at a tempo, rendered to PCM.

  Notes on a beat grid with a tempo map, rendered to one buffer that loops without a break.

      Score.from_parts([bass, arpeggio, drums], beats: 64)
      |> Score.render(44_100)
  """

  @type layer() :: TuningFork.Score.layer()
  @type t() :: TuningFork.Score.t()

  @doc """
  Place a voice on a beat.
  """
  @spec add(t(), number(), Cauldron.Audio.Voice.t()) :: t()
  def add(score, beat, voice), do: TuningFork.Score.add(score, beat, voice)

  @doc """
  Place the same voice on each of `beats`.
  """
  @spec add_all(t(), [number()], Cauldron.Audio.Voice.t()) :: t()
  def add_all(score, beats, voice), do: TuningFork.Score.add_all(score, beats, voice)

  @doc """
  Where `beat` falls, in seconds, read through the tempo map.
  """
  @spec beat_to_seconds(t(), number()) :: float()
  def beat_to_seconds(score, beat), do: TuningFork.Score.beat_to_seconds(score, beat)

  @doc """
  How long the score runs, in seconds: where `:beats` falls on the tempo map.
  """
  @spec duration(t()) :: float()
  def duration(score), do: TuningFork.Score.duration(score)

  @doc """
  Build a score by mixing parts together.

  Each part is read from its own beat zero. Every part must have the same `:bpm`; parts that
  disagree raise `ArgumentError`.

  ## Options

    * `:bpm` — the tempo, default the parts'. All parts play at it
    * `:beats` — how long the score is, default the longest part's `Cauldron.Audio.Part.beats/1`
    * `:changes` — tempo changes, as `new/1` takes them
  """
  @spec from_parts(
          [Cauldron.Audio.Part.t()],
          keyword()
        ) :: t()
  def from_parts(parts, opts \\ []), do: TuningFork.Score.from_parts(parts, opts)

  @doc """
  An empty score.

  ## Options

    * `:bpm` — the tempo it starts at, default 120
    * `:beats` — how long it runs, default 16
    * `:changes` — tempo changes after the start, as `[{beat, bpm}]`. Sorted by beat, and
      where two name the same beat the later one in the list wins
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: TuningFork.Score.new(opts)

  @doc """
  The frequency of a named note, such as `:a3`, `:fs4` or `:eb5`.
  """
  @spec note(atom() | number()) :: float()
  def note(name), do: TuningFork.Score.note(name)

  @doc """
  The frequency `interval` semitones from `name`.
  """
  @spec note(atom() | number(), integer()) :: float()
  def note(name, interval), do: TuningFork.Score.note(name, interval)

  @doc """
  Render to signed 16-bit little-endian PCM that loops without a break.

  `rate` is samples per second. The result is `duration/1` seconds long, and at least one
  frame; anything running past the end is folded back over the start. Each voice lands where
  its `:pan` says.

  ## Options

    * `:channels` — 2 for stereo, the default, or 1 for mono
  """
  @spec render(t(), pos_integer(), keyword()) :: binary()
  def render(score, rate, opts \\ []), do: TuningFork.Score.render(score, rate, opts)

  @doc """
  Place a voice every `every` beats, from `from` up to but not including `:beats`.

  Raises `ArgumentError` unless `every` is greater than zero.
  """
  @spec repeat(t(), number(), number(), Cauldron.Audio.Voice.t()) :: t()
  def repeat(score, from, every, voice), do: TuningFork.Score.repeat(score, from, every, voice)

  @doc """
  Which beat `seconds` falls on, read through the tempo map. The inverse of `beat_to_seconds/2`.
  """
  @spec seconds_to_beat(t(), number()) :: float()
  def seconds_to_beat(score, seconds), do: TuningFork.Score.seconds_to_beat(score, seconds)

  @doc """
  Change tempo at `beat`, for everything from there until the next change.

  A change at a beat that already has one replaces it. A score runs at one tempo at a time.
  """
  @spec tempo(t(), number(), number()) :: t()
  def tempo(score, beat, bpm), do: TuningFork.Score.tempo(score, beat, bpm)

  @doc """
  Every tempo this score runs at, as `[{beat, bpm}]`, starting from beat zero.

  A change stated at beat zero is the starting tempo and replaces `:bpm`.
  """
  @spec tempo_map(t()) :: [{float(), float()}]
  def tempo_map(score), do: TuningFork.Score.tempo_map(score)
end
