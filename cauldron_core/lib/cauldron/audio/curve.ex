defmodule Cauldron.Audio.Curve do
  @moduledoc """
  A value that changes over a voice's life: its pitch, its filter's cutoff or its gain (a voice's `:curves`).

  A multiplier that moves over the length of a note, as `{progress, value}` breakpoints.

      Curve.new([{0.0, 1.0}, {0.5, 1.5}, {1.0, 1.0}])
  """

  @type point() :: TuningFork.Curve.point()
  @type t() :: TuningFork.Curve.t()

  @doc """
  The value at `progress`, 0.0 at the start of a note and 1.0 at its end.

  Interpolated in a straight line between breakpoints; before the first breakpoint and after
  the last it is that breakpoint's value.
  """
  @spec at(t(), float()) :: float()
  def at(points, progress), do: TuningFork.Curve.at(points, progress)

  @doc """
  Whether a curve holds one value throughout. True of `nil` and of a single-point curve.
  """
  @spec flat?(t() | nil) :: boolean()
  def flat?(curve), do: TuningFork.Curve.flat?(curve)

  @doc """
  A curve that stays at `value` throughout. `flat?/1` is true of it.
  """
  @spec hold(number()) :: t()
  def hold(value), do: TuningFork.Curve.hold(value)

  @doc """
  A curve going straight from `from` at progress 0.0 to `to` at progress 1.0.
  """
  @spec linear(number(), number()) :: t()
  def linear(from, to), do: TuningFork.Curve.linear(from, to)

  @doc """
  A curve from `{progress, value}` pairs, sorted by progress.

  Progress runs 0.0 at the start of a note to 1.0 at its end; `value` is a multiplier over the
  field the curve is attached to. Both members of each pair are converted to floats. Raises
  `ArgumentError` on an empty list. Points outside 0.0 to 1.0 are kept rather than dropped or
  clamped.
  """
  @spec new([{number(), number()}]) :: t()
  def new(points), do: TuningFork.Curve.new(points)

  @doc """
  Thin a curve down to at most `count` breakpoints, keeping its shape.

  The first and last points are always kept. A curve already at or under `count` points is
  returned unchanged. Raises `ArgumentError` when `count` is under 2.
  """
  @spec simplify(t(), pos_integer()) :: t()
  def simplify(points, count), do: TuningFork.Curve.simplify(points, count)
end
