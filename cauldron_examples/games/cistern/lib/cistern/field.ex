defmodule Cistern.Field do
  @moduledoc """
  One keeper's square: the Squall above it, the rain in the air, and the keeper below
  carrying three jars — one balanced on the head, one hanging from each end of a yoke.

  A drop falling into a jar's mouth is caught. One that reaches the ground is a miss: it
  breaks the jar hanging on the side it fell, or the other side's when that one is gone,
  or last of all the jar on the keeper's head, and then the keeper is out. A miss also
  splashes every drop still falling and sets the storm back a step. Enough catches in a
  row mend a broken side jar. A storm ends when all its drops have come down, and the
  next is faster.

  `step/3` moves a field by `dt` seconds and answers the events it made, each placed at
  the field's own position in the world (its `offset` across), so a sound from another
  keeper's square is out of earshot.
  """

  alias Cauldron.{Rng, Tuning}
  alias Cistern.{Squall, Storm}

  @width 16
  @height 12
  @ground 11
  @keeper_row 10
  @squall_row 1
  @drop_start 1.6
  @lands_at 10.2
  @mouths %{head: {7.8, 8.5}, side: {9.3, 9.95}}
  @head_row 8.31
  @pop_seconds 0.8
  @splash_seconds 0.4

  @type side :: :left | :right
  @type slot :: side() | :head
  @type jar :: %{slot: slot(), x: float(), from: float(), until: float()}
  @type drop :: %{x: float(), y: float()}
  @type t :: %__MODULE__{}

  @enforce_keys [:id, :name, :rng]
  defstruct [
    :id,
    :name,
    :rng,
    robot?: false,
    offset: 0,
    centre: @width / 2,
    sides: MapSet.new([:left, :right]),
    held: MapSet.new(),
    aim: nil,
    squall: nil,
    drops: [],
    splashes: [],
    pops: [],
    level: 1,
    released: 0,
    until_drop: 0.0,
    lull: 0.0,
    caught: 0,
    score: 0,
    streak: 0,
    best: 1,
    out?: false
  ]

  @doc "The square's size in tiles."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: {@width, @height}

  @doc """
  The rows a drawing needs: the ground, the row the keeper stands on, the row the
  Squall floats on, and how high the head jar sits.
  """
  @spec rows() :: %{ground: integer(), keeper: integer(), squall: integer(), head: float()}
  def rows, do: %{ground: @ground, keeper: @keeper_row, squall: @squall_row, head: @head_row}

  @doc "How many jars a keeper starts with."
  @spec most_jars() :: pos_integer()
  def most_jars, do: 3

  @doc "A new square for keeper `id`, its rain from `seed`, `offset` tiles across the world."
  @spec new(term(), String.t(), integer(), keyword()) :: t()
  def new(id, name, seed, opts \\ []) do
    %__MODULE__{
      id: id,
      name: name,
      rng: Rng.new(seed),
      robot?: Keyword.get(opts, :robot?, false),
      offset: Keyword.get(opts, :offset, 0),
      squall: Squall.new(@width / 2),
      lull: Keyword.get(opts, :lull, 0.0)
    }
  end

  @doc "The field holding what its keeper holds and points at."
  @spec hold(t(), MapSet.t(atom()), {number(), number()} | nil) :: t()
  def hold(%__MODULE__{} = field, held, aim), do: %{field | held: held, aim: aim}

  @doc "How many jars the keeper still carries."
  @spec jar_count(t()) :: non_neg_integer()
  def jar_count(%__MODULE__{out?: true}), do: 0
  def jar_count(%__MODULE__{sides: sides}), do: 1 + MapSet.size(sides)

  @doc "The jars the keeper carries, each with its tile's left edge and the drop heights its mouth catches between."
  @spec jars(t()) :: [jar()]
  def jars(%__MODULE__{out?: true}), do: []

  def jars(%__MODULE__{centre: centre, sides: sides}) do
    head = jar(:head, centre - 0.5, :head)
    left = if :left in sides, do: [jar(:left, centre - 1.5, :side)], else: []
    right = if :right in sides, do: [jar(:right, centre + 0.5, :side)], else: []
    left ++ [head] ++ right
  end

  defp jar(slot, x, mouth) do
    {from, until} = Map.fetch!(@mouths, mouth)
    %{slot: slot, x: x, from: from, until: until}
  end

  @doc "The field `dt` seconds on under `tuning`, and the events of those seconds."
  @spec step(t(), number(), Tuning.t()) :: {t(), [term()]}
  def step(%__MODULE__{out?: true} = field, dt, _tuning), do: {age(field, dt), []}

  def step(%__MODULE__{} = field, dt, tuning) do
    pace = Storm.pace(tuning, field.level)

    {field, []}
    |> walk(dt, Tuning.get(tuning, :keeper_speed))
    |> drift(dt, pace)
    |> release(dt, pace)
    |> fall(dt, pace, tuning)
    |> next_storm(tuning)
    |> then(fn {moved, events} -> {age(moved, dt), Enum.reverse(events)} end)
  end

  defp walk({field, events}, dt, speed) do
    wanted =
      case field.aim do
        {x, _y} when is_number(x) -> clamp(field, x)
        _none -> clamp(field, field.centre + direction(field.held) * speed * dt)
      end

    gap = wanted - field.centre
    {%{field | centre: field.centre + min(abs(gap), speed * dt) * sign(gap)}, events}
  end

  defp direction(held) do
    cond do
      MapSet.member?(held, :left) -> -1
      MapSet.member?(held, :right) -> 1
      true -> 0
    end
  end

  defp clamp(field, x) do
    low = if :left in field.sides, do: 1.5, else: 0.5
    high = if :right in field.sides, do: @width - 1.5, else: @width - 0.5
    x |> max(low) |> min(high)
  end

  defp drift({field, events}, dt, pace) do
    {squall, rng} =
      Squall.drift(field.squall, field.rng, dt, %{
        speed: pace.squall_speed,
        swerve: pace.swerve,
        span: {1, @width - 2}
      })

    {%{field | squall: squall, rng: rng}, events}
  end

  defp release({%{lull: lull} = field, events}, dt, _pace) when lull > 0,
    do: {%{field | lull: max(0.0, lull - dt)}, events}

  defp release({field, events}, dt, pace) do
    left = field.until_drop - dt

    cond do
      field.released >= pace.drops ->
        {field, events}

      left > 0 ->
        {%{field | until_drop: left}, events}

      true ->
        drop = %{x: field.squall.x, y: @drop_start}

        {%{
           field
           | drops: [drop | field.drops],
             released: field.released + 1,
             until_drop: pace.drop_every
         }, [{:drop, place(field, drop)} | events]}
    end
  end

  defp fall({field, events}, dt, pace, tuning) do
    jars = jars(field)
    moved = Enum.map(field.drops, &%{&1 | y: &1.y + pace.fall * dt})
    {caught, rest} = Enum.split_with(moved, &catching(jars, &1))
    {landed, falling} = Enum.split_with(rest, &(&1.y >= @lands_at))

    {field, events}
    |> catches(Enum.map(caught, &{&1, catching(jars, &1)}), tuning)
    |> then(fn {f, e} -> {%{f | drops: falling}, e} end)
    |> miss(landed, tuning)
  end

  defp catching(jars, drop) do
    Enum.find(jars, fn jar ->
      drop.x >= jar.x and drop.x < jar.x + 1 and drop.y >= jar.from and drop.y < jar.until
    end)
  end

  defp catches(acc, [], _tuning), do: acc

  defp catches({field, events}, caught, tuning) do
    Enum.reduce(caught, {field, events}, fn {drop, jar}, {f, e} ->
      worth = f.level
      {mended, e} = mend(%{f | streak: f.streak + 1}, e, Tuning.get(tuning, :streak))
      pop = %{x: drop.x, y: jar.from, age: 0.0, text: "+#{worth}"}

      {%{mended | caught: f.caught + 1, score: f.score + worth, pops: [pop | f.pops]},
       [{:catch, place(f, %{drop | y: jar.from})} | e]}
    end)
  end

  defp mend(%{streak: streak, sides: sides} = field, events, needed) when streak >= needed do
    case Enum.find([:left, :right], &(&1 not in sides)) do
      nil ->
        {field, events}

      side ->
        {%{field | sides: MapSet.put(sides, side), streak: 0},
         [{:mend, place(field, %{x: field.centre, y: @keeper_row})} | events]}
    end
  end

  defp mend(field, events, _needed), do: {field, events}

  defp miss(acc, [], _tuning), do: acc

  defp miss({field, events}, [landed | _], tuning) do
    splashes = Enum.map([landed | field.drops], &%{x: &1.x, y: min(&1.y, @lands_at), age: 0.0})
    {sides, out?} = broken(field.sides, if(landed.x < field.centre, do: :left, else: :right))

    missed = %{
      field
      | sides: sides,
        drops: [],
        splashes: splashes ++ field.splashes,
        streak: 0,
        level: max(1, field.level - 1),
        released: 0,
        until_drop: 0.0,
        lull: Tuning.get(tuning, :lull),
        squall: Squall.grin(field.squall),
        out?: out?
    }

    events = [{:miss, place(field, %{landed | y: @ground})} | events]
    if out?, do: {missed, [{:out, field.id} | events]}, else: {missed, events}
  end

  defp broken(sides, toward) do
    cond do
      toward in sides -> {MapSet.delete(sides, toward), false}
      MapSet.size(sides) > 0 -> {MapSet.new(), false}
      true -> {sides, true}
    end
  end

  defp next_storm({field, events}, tuning) do
    if field.released >= Storm.pace(tuning, field.level).drops and field.drops == [] do
      level = field.level + 1

      {%{
         field
         | level: level,
           best: max(field.best, level),
           released: 0,
           lull: Tuning.get(tuning, :lull)
       }, [{{:storm, level}, place(field, %{x: field.squall.x, y: @squall_row})} | events]}
    else
      {field, events}
    end
  end

  defp age(field, dt) do
    %{
      field
      | splashes: Cauldron.Effects.step(field.splashes, dt, @splash_seconds),
        pops: Cauldron.Effects.step(field.pops, dt, @pop_seconds)
    }
  end

  defp place(field, %{x: x, y: y}), do: {field.offset + x, y}

  defp sign(gap) when gap < 0, do: -1.0
  defp sign(_gap), do: 1.0
end
