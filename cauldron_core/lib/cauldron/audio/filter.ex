defmodule Cauldron.Audio.Filter do
  @moduledoc """
  A filter a voice's sound passes through (a voice's `:filter`).

  A resonant filter, cut off at a frequency in hertz.

      Cauldron.Audio.Filter.new(hz: 800, q: 6.0, poles: 4)
  """

  @type kind() :: TuningFork.Filter.kind()
  @type model() :: TuningFork.Filter.model()
  @type state() :: TuningFork.Filter.state()
  @type t() :: TuningFork.Filter.t()

  @doc """
  Where the cutoff sits `at` seconds into a note, in hertz, with the envelope and curve
  applied. Without either this is `:hz`.
  """
  @spec cutoff_at(t(), number()) :: float()
  def cutoff_at(filter, at), do: TuningFork.Filter.cutoff_at(filter, at)

  @doc """
  The gain the signal is pushed into the ladder with: `e` to the power of `:drive`, held
  between 0.1 and 2000.0.
  """
  @spec drive(t()) :: float()
  def drive(filter), do: TuningFork.Filter.drive(filter)

  @doc """
  How hard the ladder's resonance is fed back: `:q` scaled by 0.13 and held at 8.0.

      iex> Cauldron.Audio.Filter.feedback(Cauldron.Audio.Filter.new(q: 9.0))
      1.17
      iex> Cauldron.Audio.Filter.feedback(Cauldron.Audio.Filter.new(q: 200.0))
      8.0
  """
  @spec feedback(t()) :: float()
  def feedback(filter), do: TuningFork.Filter.feedback(filter)

  @doc """
  What the ladder's output is multiplied by: `1 / drive/1` times `1 + feedback/1`, the second
  factor held at 1.75.

      iex> Cauldron.Audio.Filter.makeup(Cauldron.Audio.Filter.new(drive: 0.0, q: 0.0))
      1.0
  """
  @spec makeup(t()) :: float()
  def makeup(filter), do: TuningFork.Filter.makeup(filter)

  @doc """
  A filter from options.

  ## Options

    * `:kind` — `:lowpass`, `:highpass` or `:bandpass`, default `:lowpass`
    * `:model` — `:ladder` or `:svf`, default `:ladder`. A `:highpass` or `:bandpass` is always
      `:svf`
    * `:hz` — the cutoff in hertz, default 1200.0
    * `:q` — resonance, 0 and up; default 1.0. Values past about 62 are all as resonant as it
      goes
    * `:drive` — ladder saturation, as an exponent; default 0.69. `:svf` ignores it
    * `:poles` — 2 or 4, for `:svf` only; default 4. The ladder is always four
    * `:envelope` — a `Cauldron.Audio.Envelope` that sweeps the cutoff, or `nil`
    * `:amount` — how far the envelope sweeps, in octaves above `:hz`; default 0.0
    * `:curve` — a `Cauldron.Audio.Curve` over seconds into the note, multiplying the cutoff, or
      `nil`
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: TuningFork.Filter.new(opts)

  @doc """
  The state a filter starts from, with nothing yet stored in it.
  """
  @spec start(t() | nil) :: state()
  def start(filter), do: TuningFork.Filter.start(filter)

  @doc """
  One sample through the filter, and the state to carry to the next.

  `at` is how far into the note this sample is, in seconds; the envelope and curve are read
  against it. `rate` is samples per second. The cutoff is held between 20 Hz and `rate / 2.2`.
  """
  @spec step(t(), float(), state(), number(), pos_integer()) :: {float(), state()}
  def step(filter, sample, state, at, rate),
    do: TuningFork.Filter.step(filter, sample, state, at, rate)
end
