defmodule Cauldron.Audio.Part do
  @moduledoc """
  A part of a piece of music written as steps and notes, for `Cauldron.Audio.Score`.

  One line of music, written by moving a cursor measured in beats.

      import Cauldron.Audio.Part

      bass =
        part(bpm: 112, synth: soft_bass)
        |> play(:d2, 1.5)
        |> play(:a2, 0.5)
  """

  @type instrument() :: TuningFork.Part.instrument()
  @type step_entry() :: TuningFork.Part.step_entry()
  @type t() :: TuningFork.Part.t()

  @doc """
  Put the cursor at an exact beat, forwards or back.
  """
  @spec at(t(), number()) :: t()
  def at(part, beat), do: TuningFork.Part.at(part, beat)

  @doc """
  How far the part runs, in beats.

  The later of the cursor and the end of its last-ringing note.
  """
  @spec beats(t()) :: float()
  def beats(part), do: TuningFork.Part.beats(part)

  @doc """
  A number from `low` up to but not including `high`, and the part with its generator advanced.
  """
  @spec between(t(), number(), number()) :: {float(), t()}
  def between(part, low, high), do: TuningFork.Part.between(part, low, high)

  @doc """
  Play every note of a chord at once, then move the cursor on by `step` beats.

  `notes` is a list of note names or frequencies. `opts` are `play/4`'s and apply to every
  note of the chord.
  """
  @spec chord(t(), [atom() | number()], number(), keyword()) :: t()
  def chord(part, notes, step \\ 1.0, opts \\ []),
    do: TuningFork.Part.chord(part, notes, step, opts)

  @doc """
  Where the cursor is, in beats.
  """
  @spec cursor(t()) :: float()
  def cursor(part), do: TuningFork.Part.cursor(part)

  @doc """
  Change the part's level for everything after this point.
  """
  @spec gain(t(), number()) :: t()
  def gain(part, gain), do: TuningFork.Part.gain(part, gain)

  @doc """
  Call `fun` with the part with the given probability, and move on by `step` beats either
  way.

  `probability` runs 0.0 to 1.0 and is drawn from the part's own generator, which advances
  whether or not `fun` is called.
  """
  @spec maybe(t(), float(), (t() -> t()), number()) :: t()
  def maybe(part, probability, fun, step \\ 0.0),
    do: TuningFork.Part.maybe(part, probability, fun, step)

  @doc """
  The part's notes, as `{beat, voice}`, in the order they were played.
  """
  @spec notes(t()) :: [{float(), Cauldron.Audio.Voice.t()}]
  def notes(part), do: TuningFork.Part.notes(part)

  @doc """
  Move the part in the stereo field for everything after this point.

  Clamped to `-1.0` to `1.0`.
  """
  @spec pan(t(), number()) :: t()
  def pan(part, pan), do: TuningFork.Part.pan(part, pan)

  @doc """
  An empty part with its cursor at beat zero. Every part starts from its own beat zero; one
  that comes in later begins with `rest/2`.

  ## Options

    * `:synth` — the voice its notes are played with, or a `t:instrument/0` asked for one per
      note; default `nil`, in which case `Cauldron.Audio.Voice.new/1` is used per note
    * `:bpm` — its tempo, default 120
    * `:gain` — a level over everything in it, default 1.0
    * `:pan` — where it sits, `-1.0` hard left to `1.0` hard right, default 0.0 centred
    * `:fx` — effects applied to this part alone, as `[echo: [...], reverb: [...]]`, default
      none
    * `:seed` — seeds the part's own random generator, default 1
  """
  @spec part(keyword()) :: t()
  def part(opts \\ []), do: TuningFork.Part.part(opts)

  @doc """
  Play a run of notes, each `step` beats apart.

  `step` may be a list, whose entries are used in turn and repeat: `[0.5, 0.5, 1.0]` is two
  short and one long, over and over. `opts` are `play/4`'s and apply to every note.
  """
  @spec pattern(t(), [atom() | number()], number() | [number()], keyword()) :: t()
  def pattern(part, notes, step \\ 1.0, opts \\ []),
    do: TuningFork.Part.pattern(part, notes, step, opts)

  @doc """
  `count` independent choices from `list`, and the part with its generator advanced. The
  result may repeat an element.
  """
  @spec pick(t(), [term()], non_neg_integer()) :: {[term()], t()}
  def pick(part, list, count \\ 1), do: TuningFork.Part.pick(part, list, count)

  @doc """
  Play a note at the cursor and move the cursor on by `step` beats.

  `note` may be a note name, a frequency in Hz, or a whole `Cauldron.Audio.Voice`, which is
  played as it stands without being pitched. `step` is how long until the next note, in beats,
  independent of how long this note sounds.

  ## Options

    * `:release` — how long the note sounds, in beats. Longer than `step` overlaps the next
    * `:gain` — this note's level, multiplied by the part's
    * `:pan` — how far this note sits from where the part does, `-1.0` to `1.0`, added to the
      part's and clamped to that range
    * `:bend` — semitones to arrive at by the end of the note; `2` bends up a tone
    * `:curves` — modulation in full, as `Cauldron.Audio.Voice` takes it. A `:freq` curve given
      here supersedes `:bend`
    * `:synth` — a voice, or a `t:instrument/0`, for this note only, overriding the part's

  Any option value of the form `{:between, low, high}` is drawn from the part's own generator
  for each note.

      |> play(:e4, 0.5, release: 3.0)
      |> play(:e4, 1.0, bend: 2)
      |> play(:e4, 1.0, curves: %{gain: Curve.linear(0.2, 1.0)})
  """
  @spec play(t(), atom() | number() | Cauldron.Audio.Voice.t(), number(), keyword()) :: t()
  def play(part, note, step \\ 1.0, opts \\ []), do: TuningFork.Part.play(part, note, step, opts)

  @doc """
  Play one of `notes`, chosen by the part's own generator, and move on by `step` beats.

  The same seed picks the same notes in the same order. `opts` are `play/4`'s.
  """
  @spec play_any(t(), [atom() | number() | Cauldron.Audio.Voice.t()], number(), keyword()) :: t()
  def play_any(part, notes, step \\ 1.0, opts \\ []),
    do: TuningFork.Part.play_any(part, notes, step, opts)

  @doc """
  Apply `fun` to the part `times` over, from wherever the cursor is.

  `times` may instead be a string of `x` and `.`, one per pass: `fun` is applied on an `x`,
  and on a `.` the cursor moves on by as much as `fun` would have moved it, playing nothing.

      |> repeat(4, &steps(&1, "x...x..."))
      |> repeat("..xx", &steps(&1, "x...x..."))
  """
  @spec repeat(t(), pos_integer() | String.t(), (t() -> t())) :: t()
  def repeat(part, passes, fun), do: TuningFork.Part.repeat(part, passes, fun)

  @doc """
  Apply `fun` to the part `times` over, told which pass it is, counting from zero.
  """
  @spec repeat_indexed(t(), pos_integer(), (t(), non_neg_integer() -> t())) :: t()
  def repeat_indexed(part, times, fun), do: TuningFork.Part.repeat_indexed(part, times, fun)

  @doc """
  Move the cursor on by `beats` without playing anything.
  """
  @spec rest(t(), number()) :: t()
  def rest(part, beats), do: TuningFork.Part.rest(part, beats)

  @doc """
  Play a pattern of evenly spaced steps, each `step` beats apart.

  A string plays the part's own synth on `x` or `X`, plays at a ninth of full level on a digit
  `1` to `9` (multiplied into any `:gain` given), and rests on any other character. Spaces
  are ignored. `step` defaults to 0.25.

      |> steps("x..x..x.")
      |> steps("x2x2x9x2", 0.25)

  A list places a different entry on each step. An entry is anything `play/4` accepts, `nil`
  for a rest, or `{note, opts}` for one step carrying its own options merged over `opts`:

      |> steps([{:a3, release: 4.0}, nil, :c4, nil, :e4, nil, nil, nil])
  """
  @spec steps(t(), String.t() | [step_entry()], number(), keyword()) :: t()
  def steps(part, pattern, step \\ 0.25, opts \\ []),
    do: TuningFork.Part.steps(part, pattern, step, opts)

  @doc """
  Change the voice, or `t:instrument/0`, used for everything after this point.
  """
  @spec synth(t(), Cauldron.Audio.Voice.t() | instrument()) :: t()
  def synth(part, voice), do: TuningFork.Part.synth(part, voice)

  @doc """
  Play a note without moving the cursor, for stacking a chord. Takes `play/4`'s options.
  """
  @spec under(t(), atom() | number() | Cauldron.Audio.Voice.t(), keyword()) :: t()
  def under(part, note, opts \\ []), do: TuningFork.Part.under(part, note, opts)
end
