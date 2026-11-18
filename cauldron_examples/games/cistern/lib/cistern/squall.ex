defmodule Cistern.Squall do
  @moduledoc """
  The storm cloud that drifts along the top of a field and lets the rain go: where it
  is, where it is heading, and its mood, which a client draws on its face.

  It drifts towards a column it chose and, there, chooses another; now and then it turns
  early, more often the wilder the storm. After a miss it grins for a moment.
  """

  alias Cauldron.Rng

  @mood_seconds 1.5

  @type mood :: :calm | :grin
  @type t :: %{x: float(), target: float(), mood: mood(), mood_left: float()}

  @doc "A Squall at `x`, heading nowhere yet."
  @spec new(number()) :: t()
  def new(x), do: %{x: x / 1, target: x / 1, mood: :calm, mood_left: 0.0}

  @doc """
  The Squall `dt` seconds on, drifting at `speed` tiles a second within `low..high`
  columns, turning early at `swerve` chances a second; with the generator after any
  choice it made.
  """
  @spec drift(t(), Rng.t(), number(), %{
          speed: number(),
          swerve: number(),
          span: {integer(), integer()}
        }) ::
          {t(), Rng.t()}
  def drift(squall, rng, dt, %{speed: speed, swerve: swerve, span: span}) do
    {squall, rng} = maybe_turn(squall, rng, dt, swerve, span)
    gap = squall.target - squall.x
    step = min(abs(gap), speed * dt)
    moved = %{squall | x: squall.x + step * sign(gap)} |> calm_down(dt)

    if abs(moved.target - moved.x) < 0.01, do: choose(moved, rng, span), else: {moved, rng}
  end

  @doc "The Squall grinning, as it does after a miss."
  @spec grin(t()) :: t()
  def grin(squall), do: %{squall | mood: :grin, mood_left: @mood_seconds}

  defp maybe_turn(squall, rng, dt, swerve, span) do
    {roll, rng} = Rng.roll(rng, 1000)
    if roll <= swerve * dt * 1000, do: choose(squall, rng, span), else: {squall, rng}
  end

  defp choose(squall, rng, {low, high}) do
    {column, rng} = Rng.between(rng, low, high)
    {%{squall | target: column + 0.5}, rng}
  end

  defp calm_down(%{mood_left: left} = squall, dt) when left > dt,
    do: %{squall | mood_left: left - dt}

  defp calm_down(squall, _dt), do: %{squall | mood: :calm, mood_left: 0.0}

  defp sign(gap) when gap < 0, do: -1.0
  defp sign(_gap), do: 1.0
end
