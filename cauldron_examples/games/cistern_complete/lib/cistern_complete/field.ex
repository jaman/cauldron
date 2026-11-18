defmodule CisternComplete.Field do
  @moduledoc """
  One keeper's square: the Squall above, the rain and hail in the air, lightning when
  the storm brings it, the cistern's grate in the middle of the cobbles, and the keeper
  below with three jars.

  Jars fill as they catch. Standing over the grate and holding `:pour` empties them into
  the cistern; what is poured scores the storm's number a drop, twice that when every
  jar was full. Pouring three full jars sends a gust to every rival's Squall (the
  `{:gust, id}` event, which `CisternComplete.Game` hands on). The rest of the rules are
  `CisternComplete.Rain`'s, `CisternComplete.Mishap`'s and `CisternComplete.Lightning`'s.

  `step/3` moves a square by `dt` seconds and answers its events, each placed at the
  square's own position in the world (its `offset` across), so a sound from another
  keeper's square is out of earshot.
  """

  alias Cauldron.{Rng, Tuning}
  alias CisternComplete.{Lightning, Rain, Squall, Storm, Yoke}

  @width 16
  @height 12

  @type t :: %__MODULE__{}

  @enforce_keys [:id, :name, :rng, :squall]
  defstruct [
    :id,
    :name,
    :rng,
    :squall,
    robot?: false,
    offset: 0,
    yoke: %Yoke{},
    held: MapSet.new(),
    aim: nil,
    drops: [],
    splashes: [],
    pops: [],
    bolts: [],
    strike: nil,
    until_strike: 0.0,
    pouring: 0.0,
    level: 1,
    released: 0,
    until_drop: 0.0,
    lull: 0.0,
    water: 0,
    score: 0,
    streak: 0,
    best: 1,
    clock: 0.0,
    out?: false
  ]

  @doc "The square's size in tiles."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: {@width, @height}

  @doc "A new square for keeper `id`, its rain from `seed`, `offset` tiles across the world, under `tuning`."
  @spec new(term(), String.t(), integer(), Tuning.t(), keyword()) :: t()
  def new(id, name, seed, tuning, opts \\ []) do
    %__MODULE__{
      id: id,
      name: name,
      rng: Rng.new(seed),
      squall: Squall.new(@width / 2, Tuning.get(tuning, :mood_every)),
      robot?: Keyword.get(opts, :robot?, false),
      offset: Keyword.get(opts, :offset, 0),
      lull: Tuning.get(tuning, :lull),
      until_strike: Tuning.get(tuning, :lightning_every)
    }
  end

  @doc "The field holding what its keeper holds and points at."
  @spec hold(t(), MapSet.t(atom()), {number(), number()} | nil) :: t()
  def hold(%__MODULE__{} = field, held, aim), do: %{field | held: held, aim: aim}

  @doc "The field's Squall gusting, as a rival's pour makes it."
  @spec gusted(t(), Tuning.t()) :: t()
  def gusted(%__MODULE__{} = field, tuning),
    do: %{field | squall: Squall.gust(field.squall, Tuning.get(tuning, :gust_seconds))}

  @doc "Where an event at `{x, y}` in the square sounds from in the world."
  @spec place(t(), %{x: number(), y: number()}) :: {number(), number()}
  def place(field, %{x: x, y: y}), do: {field.offset + x, y}

  @doc "The field `dt` seconds on under `tuning`, and the events of those seconds."
  @spec step(t(), number(), Tuning.t()) :: {t(), [term()]}
  def step(%__MODULE__{out?: true} = field, dt, _tuning), do: {age(field, dt), []}

  def step(%__MODULE__{} = field, dt, tuning) do
    pace = Storm.pace(tuning, field.level)

    {field, []}
    |> walk(dt, Tuning.get(tuning, :keeper_speed))
    |> pour(dt, tuning)
    |> drift(dt, pace, tuning)
    |> Rain.release(dt, pace)
    |> Rain.fall(dt, pace, tuning)
    |> Lightning.step(dt, pace, tuning)
    |> next_storm(tuning)
    |> then(fn {moved, events} -> {age(moved, dt), Enum.reverse(events)} end)
  end

  defp walk({%{pouring: pouring} = field, events}, _dt, _speed) when pouring > 0,
    do: {field, events}

  defp walk({field, events}, dt, speed) do
    wanted =
      case field.aim do
        {x, _y} when is_number(x) -> x
        _none -> field.yoke.centre + direction(field.held) * speed * dt
      end

    {%{field | yoke: Yoke.walk(field.yoke, wanted, speed * dt)}, events}
  end

  defp direction(held) do
    cond do
      MapSet.member?(held, :left) -> -1
      MapSet.member?(held, :right) -> 1
      true -> 0
    end
  end

  defp pour({%{pouring: pouring} = field, events}, dt, tuning) when pouring > 0 do
    if pouring > dt,
      do: {%{field | pouring: pouring - dt}, events},
      else: poured({field, events}, tuning)
  end

  defp pour({field, events}, _dt, tuning) do
    if MapSet.member?(field.held, :pour) and Yoke.over_grate?(field.yoke) and
         Yoke.water(field.yoke) > 0,
       do:
         {%{field | pouring: Tuning.get(tuning, :pour_seconds)},
          [{:pouring, place(field, %{x: field.yoke.centre, y: 10})} | events]},
       else: {field, events}
  end

  defp poured({field, events}, tuning) do
    full? = Yoke.all_full?(field.yoke, Tuning.get(tuning, :capacity))
    {yoke, drops} = Yoke.pour(field.yoke)
    points = drops * field.level * if(full?, do: 2, else: 1)
    pop = %{x: field.yoke.centre, y: 9.0, age: 0.0, text: "+#{points}"}

    poured = %{
      field
      | yoke: yoke,
        pouring: 0.0,
        water: field.water + drops,
        score: field.score + points,
        pops: [pop | field.pops]
    }

    events = [{:pour, place(field, %{x: field.yoke.centre, y: 11})} | events]

    if full? and Yoke.count(yoke) == 3,
      do: {poured, [{:gust, field.id} | events]},
      else: {poured, events}
  end

  defp drift({field, events}, dt, pace, tuning) do
    {squall, rng, burst?} =
      Squall.drift(field.squall, field.rng, dt, %{
        speed: pace.squall_speed,
        swerve: pace.swerve,
        span: {1, @width - 2},
        level: field.level,
        mood_every: Tuning.get(tuning, :mood_every),
        gust_seconds: Tuning.get(tuning, :gust_seconds)
      })

    moved = {%{field | squall: squall, rng: rng}, events}
    if burst? and field.lull == 0, do: Rain.burst(moved, pace), else: moved
  end

  defp next_storm({field, events}, tuning) do
    if field.released >= Storm.pace(tuning, field.level).drops and field.drops == [] and
         not field.out? do
      level = field.level + 1

      quiet = %{
        field
        | level: level,
          best: max(field.best, level),
          released: 0,
          lull: Tuning.get(tuning, :lull),
          strike: nil
      }

      {quiet, [{{:storm, level}, place(field, %{x: field.squall.x, y: 1})} | events]}
    else
      {field, events}
    end
  end

  defp age(field, dt) do
    %{
      field
      | clock: field.clock + dt,
        splashes: Cauldron.Effects.step(field.splashes, dt, 0.4),
        pops: Cauldron.Effects.step(field.pops, dt, 0.9)
    }
  end
end
