defmodule Megablast.Wave do
  @moduledoc """
  Waves of creatures: a formation of one kind entering together and flying one path.

  A `new/1` value holds how the waves move; the game carries it. `next/5` gives the
  creatures of a wave, each stamped with the numbers its own path needs, so `fly/2` is
  arithmetic on the creature and nothing else.

  Every number is a setting of `new/1`, defaulting to `config :megablast, <key>, value` and
  then to the figure declared here.

  ## Settings

    * `:wave_spread` — how far apart creatures stand in a formation, in tiles
    * `:sweep_reach` — how far a sweeping creature swings either side of its lane, in tiles
    * `:sweep_rate` — how fast it swings, in radians a second
    * `:dive_speed` — how fast a diving creature falls, in tiles a second
    * `:drift_speed` — how fast a drifting creature falls, in tiles a second
    * `:arc_reach` — how far an arcing creature swings, in tiles
  """

  alias Cauldron2D.Rng
  alias Megablast.Lane

  @shapes [
    %{kind: :drone, count: 5, shape: :line, path: :sweep},
    %{kind: :drone, count: 4, shape: :vee, path: :dive},
    %{kind: :mine, count: 3, shape: :line, path: :drift},
    %{kind: :drone, count: 6, shape: :arc, path: :arc},
    %{kind: :drone, count: 3, shape: :column, path: :sweep},
    %{kind: :mine, count: 4, shape: :vee, path: :drift}
  ]

  @defaults [
    wave_spread: 2.2,
    sweep_reach: 3.4,
    sweep_rate: 1.3,
    dive_speed: 7.0,
    drift_speed: 2.4,
    arc_reach: 4.2
  ]

  @type t :: %__MODULE__{
          spread: float(),
          sweep_reach: float(),
          sweep_rate: float(),
          dive: float(),
          drift: float(),
          arc: float()
        }

  @type creature :: %{
          kind: atom(),
          x: float(),
          y: float(),
          path: atom(),
          lane: float(),
          phase: float(),
          age: float(),
          fall: float(),
          reach: float(),
          rate: float()
        }

  @enforce_keys [:spread, :sweep_reach, :sweep_rate, :dive, :drift, :arc]
  defstruct [:spread, :sweep_reach, :sweep_rate, :dive, :drift, :arc]

  @doc "The wave settings from `overrides`, over the configured defaults."
  @spec new(keyword()) :: t()
  def new(overrides \\ []) do
    %__MODULE__{
      spread: setting(overrides, :wave_spread),
      sweep_reach: setting(overrides, :sweep_reach),
      sweep_rate: setting(overrides, :sweep_rate),
      dive: setting(overrides, :dive_speed),
      drift: setting(overrides, :drift_speed),
      arc: setting(overrides, :arc_reach)
    }
  end

  @doc "The settings and the figures they fall back to."
  @spec defaults() :: keyword()
  def defaults, do: @defaults

  @doc "How many waves there are to cycle through."
  @spec count() :: pos_integer()
  def count, do: length(@shapes)

  @doc "The creatures of wave `number`, entering at row `y` of `lane`."
  @spec next(t(), non_neg_integer(), number(), Rng.t(), Lane.t()) :: {[creature()], Rng.t()}
  def next(%__MODULE__{} = waves, number, y, rng, lane) do
    shape = Enum.at(@shapes, Integer.mod(number, length(@shapes)))
    {left, right} = Lane.edges(lane, y)
    low = ceil(left + waves.spread)
    {centre, rng} = Rng.between(rng, low, max(low, floor(right - waves.spread)))

    creatures =
      shape
      |> places(waves, centre, {left, right})
      |> Enum.with_index()
      |> Enum.map(fn {place, index} -> creature(shape, waves, place, index, y) end)

    {creatures, rng}
  end

  @doc "One creature moved `dt` seconds along its path."
  @spec fly(creature(), number()) :: creature()
  def fly(creature, dt) do
    age = creature.age + dt

    creature
    |> Map.put(:age, age)
    |> Map.put(:x, across(creature, age))
    |> Map.put(:y, creature.y + creature.fall * dt)
  end

  defp setting(overrides, key) do
    Keyword.get_lazy(overrides, key, fn ->
      Application.get_env(:megablast, key, Keyword.fetch!(@defaults, key))
    end)
  end

  defp places(%{shape: shape, count: count}, waves, centre, {left, right}) do
    for index <- 0..(count - 1) do
      offset = (index - (count - 1) / 2) * waves.spread

      {clamp(centre + offset, left + 0.6, right - 0.6), tier(shape, index, count)}
    end
  end

  defp tier(:line, _index, _count), do: 0.0
  defp tier(:column, index, _count), do: index * 2.4
  defp tier(:vee, index, count), do: abs(index - (count - 1) / 2) * 1.6
  defp tier(:arc, index, count), do: (1.0 - abs(index - (count - 1) / 2) / count) * 2.2

  defp creature(shape, waves, {x, back}, index, y) do
    %{
      kind: shape.kind,
      x: x / 1,
      y: y - back,
      path: shape.path,
      lane: x / 1,
      phase: index * 0.7,
      age: 0.0,
      fall: fall(shape.path, waves),
      reach: reach(shape.path, waves),
      rate: rate(shape.path, waves)
    }
  end

  defp fall(:dive, waves), do: waves.dive
  defp fall(:drift, waves), do: waves.drift
  defp fall(_path, waves), do: waves.drift * 1.4

  defp reach(:sweep, waves), do: waves.sweep_reach
  defp reach(:arc, waves), do: waves.arc
  defp reach(_path, _waves), do: 0.0

  defp rate(:sweep, waves), do: waves.sweep_rate
  defp rate(:arc, _waves), do: 0.8
  defp rate(_path, _waves), do: 0.0

  defp across(%{reach: reach} = creature, _age) when reach == 0, do: creature.x

  defp across(creature, age),
    do: creature.lane + :math.sin(age * creature.rate + creature.phase) * creature.reach

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
