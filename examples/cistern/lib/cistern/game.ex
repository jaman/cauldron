defmodule Cistern.Game do
  @moduledoc """
  A game of catching drops: every player holds a bucket two tiles wide on the row above
  the floor of a twelve-by-ten field, drops fall from the top, and a drop that reaches
  the bucket's own row over the bucket lands in it. One that is not over a bucket falls
  the last row and splashes on the floor. A gold drop is worth three. Three misses and
  that player is out.

  This is a `Cauldron2D.Game`: `init/1` builds it, `join/3` seats a bucket, `step/2` moves
  the world by `dt` seconds, `view/2` is what one player sees, and `drain_events/1` is
  what happened since it was last asked. Nothing here reads a clock or draws.

  ## Options

    * `:seed` — the generator's seed, so a game replays the same. Default: fresh
    * `:tuning` — overrides on `Cistern.Tuning`'s defaults
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.{Rng, Tuning}
  alias Cistern.Tuning, as: Settings

  @width 12
  @height 10
  @bottom @height - 1
  @caught_at @bottom - 1
  @bucket_wide 2.0
  @speed 8.0
  @misses_allowed 3

  @type bucket :: %{
          id: term(),
          name: String.t(),
          x: float(),
          score: non_neg_integer(),
          misses: non_neg_integer(),
          held: MapSet.t(atom()),
          aim: {number(), number()} | nil,
          robot?: boolean()
        }
  @type drop :: %{x: non_neg_integer(), y: float(), kind: :drop | :drop_gold}
  @type t :: %__MODULE__{
          buckets: %{term() => bucket()},
          drops: [drop()],
          rng: Rng.t(),
          tuning: Tuning.t(),
          until_next: float(),
          events: [term()]
        }

  defstruct buckets: %{}, drops: [], rng: nil, tuning: nil, until_next: 0.0, events: []

  @doc "The field's size in tiles."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: {@width, @height}

  @impl true
  def init(opts) do
    {rng, _seed} =
      case Keyword.get(opts, :seed) do
        nil -> Rng.random()
        seed -> {Rng.new(seed), seed}
      end

    tuning = Settings.new(Keyword.get(opts, :tuning, []))
    %__MODULE__{rng: rng, tuning: tuning, until_next: Tuning.get(tuning, :spawn_every)}
  end

  @impl true
  def join(%__MODULE__{} = game, id, props) do
    bucket = %{
      id: id,
      name: Map.get(props, :username, "player"),
      x: @width / 2 - 1,
      score: 0,
      misses: 0,
      held: MapSet.new(),
      aim: nil,
      robot?: Map.get(props, :robot?, false)
    }

    {:ok, %{game | buckets: Map.put(game.buckets, id, bucket)}}
  end

  @impl true
  def leave(%__MODULE__{} = game, id), do: %{game | buckets: Map.delete(game.buckets, id)}

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case Map.fetch(game.buckets, id) do
      {:ok, bucket} ->
        %{
          game
          | buckets: Map.put(game.buckets, id, %{bucket | held: held, aim: Map.get(input, :aim)})
        }

      :error ->
        game
    end
  end

  @impl true
  def step(%__MODULE__{} = game, dt) do
    game
    |> steer(dt)
    |> spawn_drop(dt)
    |> fall(dt)
  end

  defp steer(game, dt) do
    buckets = Map.new(game.buckets, fn {id, bucket} -> {id, steered(bucket, dt)} end)
    %{game | buckets: buckets}
  end

  defp steered(%{misses: misses} = bucket, _dt) when misses >= @misses_allowed, do: bucket

  defp steered(%{aim: {x, _y}} = bucket, dt) when is_number(x) do
    target = clamp(x - @bucket_wide / 2)
    step = min(abs(target - bucket.x), @speed * dt)
    %{bucket | x: bucket.x + step * sign(target - bucket.x)}
  end

  defp steered(bucket, dt) do
    direction =
      cond do
        MapSet.member?(bucket.held, :left) -> -1
        MapSet.member?(bucket.held, :right) -> 1
        true -> 0
      end

    %{bucket | x: clamp(bucket.x + direction * @speed * dt)}
  end

  defp clamp(x), do: x |> max(0.0) |> min(@width - @bucket_wide)

  defp sign(n) when n < 0, do: -1.0
  defp sign(_n), do: 1.0

  defp spawn_drop(%__MODULE__{until_next: left} = game, dt) when left > dt,
    do: %{game | until_next: left - dt}

  defp spawn_drop(game, _dt) do
    {column, rng} = Rng.roll(game.rng, @width)
    {gold?, rng} = Rng.chance(rng, 1, 6)
    drop = %{x: column - 1, y: 0.0, kind: if(gold?, do: :drop_gold, else: :drop)}

    %{
      game
      | rng: rng,
        drops: [drop | game.drops],
        until_next: Tuning.get(game.tuning, :spawn_every)
    }
  end

  defp fall(game, dt) do
    playing = playing(game)

    {settling, falling} =
      game.drops
      |> Enum.map(&%{&1 | y: &1.y + Tuning.get(game.tuning, :fall) * dt})
      |> Enum.split_with(&(&1.y >= @caught_at))

    Enum.reduce(settling, %{game | drops: falling}, &settle(&2, &1, playing))
  end

  defp settle(game, drop, playing) do
    case Enum.find(playing, &under?(&1, drop)) do
      nil -> fell_past(game, drop)
      bucket -> catch_drop(game, bucket, drop)
    end
  end

  defp fell_past(game, %{y: y} = drop) when y >= @bottom, do: miss(game, drop)
  defp fell_past(game, drop), do: %{game | drops: [drop | game.drops]}

  defp playing(game),
    do: game.buckets |> Map.values() |> Enum.filter(&(&1.misses < @misses_allowed))

  defp under?(bucket, drop) do
    middle = drop.x + 0.5
    middle >= bucket.x and middle <= bucket.x + @bucket_wide
  end

  @doc "How wide a bucket is, in tiles."
  @spec bucket_wide() :: float()
  def bucket_wide, do: @bucket_wide

  @doc "The row a drop is caught on, which is the row a bucket stands on."
  @spec caught_at() :: non_neg_integer()
  def caught_at, do: @caught_at

  defp catch_drop(game, bucket, drop) do
    worth = if drop.kind == :drop_gold, do: 3, else: 1
    caught = %{bucket | score: bucket.score + worth}

    %{game | buckets: Map.put(game.buckets, bucket.id, caught)}
    |> emit({:catch, drop.kind, {drop.x, @bottom}})
  end

  defp miss(game, drop) do
    buckets = Map.new(game.buckets, fn {id, bucket} -> {id, missed(bucket)} end)

    %{game | buckets: buckets}
    |> emit({:splash, {drop.x, @bottom}})
    |> then(fn acc -> Enum.reduce(Map.values(acc.buckets), acc, &out(&2, &1)) end)
  end

  defp missed(%{misses: misses} = bucket) when misses < @misses_allowed,
    do: %{bucket | misses: misses + 1}

  defp missed(bucket), do: bucket

  defp out(game, %{misses: @misses_allowed} = bucket) do
    if Enum.any?(game.events, &(&1 == {:out, bucket.id})),
      do: game,
      else: emit(game, {:out, bucket.id})
  end

  defp out(game, _bucket), do: game

  @impl true
  def view(%__MODULE__{} = game, id) do
    %{
      me: Map.get(game.buckets, id),
      buckets: Map.values(game.buckets),
      drops: game.drops,
      size: size(),
      misses_allowed: @misses_allowed
    }
  end

  @impl true
  def drain_events(%__MODULE__{events: events} = game),
    do: {Enum.reverse(events), %{game | events: []}}

  defp emit(game, event), do: %{game | events: [event | game.events]}

  @doc "The outcome for the player of `view`: `nil` while they play, or the summary once they are out."
  @spec outcome(map()) :: map() | nil
  def outcome(%{me: nil}), do: nil

  def outcome(%{me: me, misses_allowed: allowed} = view) when me.misses >= allowed do
    best = view.buckets |> Enum.map(& &1.score) |> Enum.max()

    %{
      title: "The cistern overflows",
      lines: [
        "#{me.score} caught",
        if(me.score >= best, do: "the fullest bucket", else: "best was #{best}")
      ],
      next: :same_world
    }
  end

  def outcome(_view), do: nil
end
