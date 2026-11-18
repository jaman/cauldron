defmodule CisternComplete.Squall do
  @moduledoc """
  The storm cloud: where it drifts, and its mood, which a player learns to read from its
  face.

    * `:drizzle` — it drifts and lets the rain go at the storm's pace
    * `:gust` — it races, three times as fast, and sprays rain twice as often
    * `:sulk` — it stops and swells, letting nothing go; when the sulk ends it bursts,
      a spread of drops at once
    * `:grin` — after a miss, a moment of drizzle with a grin

  Moods change every few seconds, chosen by the storm: the first storm only drizzles,
  the second adds gusts, the third and after add sulks. A gust can also be forced — a
  rival's good pour sends one.
  """

  alias Cauldron.Rng

  @grin_seconds 1.5
  @sulk_seconds 1.6

  @type mood :: :drizzle | :gust | :sulk | :grin
  @type t :: %{
          x: float(),
          target: float(),
          mood: mood(),
          mood_left: float()
        }
  @type pace :: %{
          speed: number(),
          swerve: number(),
          span: {integer(), integer()},
          level: pos_integer(),
          mood_every: number(),
          gust_seconds: number()
        }

  @doc "A Squall at `x`, drizzling."
  @spec new(number(), number()) :: t()
  def new(x, mood_every),
    do: %{x: x / 1, target: x / 1, mood: :drizzle, mood_left: mood_every / 1}

  @doc """
  The Squall `dt` seconds on, the generator after any choice it made, and whether it
  burst: a sulk that ended in those seconds.
  """
  @spec drift(t(), Rng.t(), number(), pace()) :: {t(), Rng.t(), boolean()}
  def drift(squall, rng, dt, pace) do
    {squall, rng} = maybe_turn(squall, rng, dt, pace)
    {moved, rng} = squall |> move(dt, pace.speed * speed(squall.mood)) |> arrive(rng, pace.span)
    left = moved.mood_left - dt

    if left > 0 do
      {%{moved | mood_left: left}, rng, false}
    else
      {next, rng} = next_mood(rng, pace.level)
      {%{moved | mood: next, mood_left: seconds(next, pace)}, rng, moved.mood == :sulk}
    end
  end

  @doc "The Squall grinning, as it does after a miss."
  @spec grin(t()) :: t()
  def grin(squall), do: %{squall | mood: :grin, mood_left: @grin_seconds}

  @doc "The Squall gusting for `seconds`, as a rival's pour makes it."
  @spec gust(t(), number()) :: t()
  def gust(squall, seconds), do: %{squall | mood: :gust, mood_left: seconds / 1}

  @doc "How much more often than the storm's pace the Squall drops, or `nil` while it lets nothing go."
  @spec drop_rate(t()) :: number() | nil
  def drop_rate(%{mood: :sulk}), do: nil
  def drop_rate(%{mood: :gust}), do: 2.0
  def drop_rate(_squall), do: 1.0

  defp speed(:gust), do: 3.0
  defp speed(:sulk), do: 0.0
  defp speed(_mood), do: 1.0

  defp seconds(:sulk, _pace), do: @sulk_seconds
  defp seconds(:gust, pace), do: pace.gust_seconds
  defp seconds(_mood, pace), do: pace.mood_every

  defp next_mood(rng, level) do
    choices =
      [{5, :drizzle}] ++
        if(level >= 2, do: [{2, :gust}], else: []) ++
        if(level >= 3, do: [{2, :sulk}], else: [])

    {mood, rng} = Rng.weighted(rng, choices)
    {mood, rng}
  end

  defp move(squall, dt, speed) do
    gap = squall.target - squall.x
    %{squall | x: squall.x + min(abs(gap), speed * dt) * sign(gap)}
  end

  defp arrive(squall, rng, span) do
    if abs(squall.target - squall.x) < 0.01, do: choose(squall, rng, span), else: {squall, rng}
  end

  defp maybe_turn(squall, rng, dt, pace) do
    {roll, rng} = Rng.roll(rng, 1000)
    if roll <= pace.swerve * dt * 1000, do: choose(squall, rng, pace.span), else: {squall, rng}
  end

  defp choose(squall, rng, {low, high}) do
    {column, rng} = Rng.between(rng, low, high)
    {%{squall | target: column + 0.5}, rng}
  end

  defp sign(gap) when gap < 0, do: -1.0
  defp sign(_gap), do: 1.0
end
