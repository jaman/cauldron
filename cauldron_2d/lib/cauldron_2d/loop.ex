defmodule Cauldron2D.Loop do
  @moduledoc """
  A fixed timestep.

      loop = Cauldron2D.Loop.new(60)

      {steps, loop} = Cauldron2D.Loop.advance(loop, Cauldron2D.Loop.now())
      world = Enum.reduce(1..steps//1, world, fn _, w -> World.step(w, Cauldron2D.Loop.dt(loop)) end)

  `advance/2` returns how many whole steps have come due since it was last called. `dt/1` is
  constant, so a simulation driven by it runs at the same speed whatever the frame rate and
  replays identically given the same inputs.

  Rules a caller must respect:

    * The first `advance/2` call establishes the baseline and returns no steps.
    * At most `:max_steps` are returned from one call. Time beyond that is discarded rather
      than carried, so the simulation loses that time instead of owing a backlog.
    * Time below one step is carried in the accumulator and returned by a later call.
    * A `now_ms` earlier than the previous one contributes nothing; steps are never negative.
  """

  @type t :: %__MODULE__{
          step_ms: float(),
          max_steps: pos_integer(),
          accumulator: float(),
          last: integer() | nil
        }

  defstruct [:step_ms, :max_steps, accumulator: 0.0, last: nil]

  @doc """
  A loop running at `hz` steps per second. `hz` must be positive.

  ## Options

    * `:max_steps` — the most steps one `advance/2` call may return before the remaining time
      is discarded. Default 5
  """
  @spec new(number(), keyword()) :: t()
  def new(hz, opts \\ []) when hz > 0 do
    %__MODULE__{step_ms: 1000 / hz, max_steps: Keyword.get(opts, :max_steps, 5)}
  end

  @doc """
  How many whole steps are due at `now_ms`, and the loop to carry forward.

  `now_ms` is a millisecond reading on a single monotonic scale, as `now/0` returns. Returns
  `{steps, loop}`; pass the returned loop to the next call.

  The first call on a fresh loop records `now_ms` as the baseline and returns 0 steps,
  whatever the interval since `new/2`.
  """
  @spec advance(t(), integer()) :: {non_neg_integer(), t()}
  def advance(%__MODULE__{last: nil} = loop, now_ms), do: {0, %{loop | last: now_ms}}

  def advance(%__MODULE__{} = loop, now_ms) do
    accumulated = loop.accumulator + max(0, now_ms - loop.last)
    due = trunc(accumulated / loop.step_ms)
    steps = min(due, loop.max_steps)

    remainder =
      if due > loop.max_steps do
        0.0
      else
        accumulated - steps * loop.step_ms
      end

    {steps, %{loop | accumulator: remainder, last: now_ms}}
  end

  @doc """
  The whole milliseconds from `now_ms` until `advance/2` would next return a step: 0 when
  one is already due, or when the loop has no baseline yet.
  """
  @spec wait(t(), integer()) :: non_neg_integer()
  def wait(%__MODULE__{last: nil}, _now_ms), do: 0

  def wait(%__MODULE__{} = loop, now_ms) do
    accumulated = loop.accumulator + max(0, now_ms - loop.last)
    max(0, ceil(loop.step_ms - accumulated))
  end

  @doc "The duration of one step, in seconds — the `dt` a simulation should use."
  @spec dt(t()) :: float()
  def dt(%__MODULE__{step_ms: step_ms}), do: step_ms / 1000

  @doc "The current monotonic time in milliseconds, in the form `advance/2` expects."
  @spec now() :: integer()
  def now, do: System.monotonic_time(:millisecond)
end
