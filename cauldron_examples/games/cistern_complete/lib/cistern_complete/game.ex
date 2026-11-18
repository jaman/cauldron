defmodule CisternComplete.Game do
  @moduledoc """
  The town in drought and the storm that will not rain on the cistern. Every keeper —
  each player, each robot — has a square of their own, side by side, rained on from the
  same seed. A keeper's good pour sends a gust to every other keeper's Squall. The rules
  of a square are `CisternComplete.Field`'s.

  This is a `Cauldron.Game`. Nothing here reads a clock or draws.

  ## Options

    * `:seed` — the generator's seed, so a game replays the same. Default: fresh
    * `:tuning` — overrides on `CisternComplete.Tuning`'s defaults
  """

  @behaviour Cauldron.Game

  alias Cauldron.Rng
  alias CisternComplete.{Field, Yoke}
  alias CisternComplete.Tuning, as: Settings

  @apart 100

  defstruct fields: %{}, seed: 0, tuning: nil, seats: 0, events: []

  @type t :: %__MODULE__{}

  @impl true
  def init(opts) do
    seed = Keyword.get_lazy(opts, :seed, fn -> Rng.random() |> elem(1) end)
    %__MODULE__{seed: seed, tuning: Settings.new(Keyword.get(opts, :tuning, []))}
  end

  @impl true
  def join(%__MODULE__{} = game, id, props) do
    field =
      Field.new(id, Map.get(props, :username, "keeper"), game.seed, game.tuning,
        robot?: Map.get(props, :robot?, false),
        offset: game.seats * @apart
      )

    {:ok, %{game | fields: Map.put(game.fields, id, field), seats: game.seats + 1}}
  end

  @impl true
  def leave(%__MODULE__{} = game, id), do: %{game | fields: Map.delete(game.fields, id)}

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case Map.fetch(game.fields, id) do
      {:ok, field} -> put_in(game.fields[id], Field.hold(field, held, Map.get(input, :aim)))
      :error -> game
    end
  end

  @impl true
  def step(%__MODULE__{} = game, dt) do
    {fields, events} =
      Enum.reduce(game.fields, {game.fields, []}, fn {id, field}, {fields, acc} ->
        {stepped, events} = Field.step(field, dt, game.tuning)
        {Map.put(fields, id, stepped), acc ++ events}
      end)

    gusted = Enum.reduce(events, fields, &send_gust(&1, &2, game.tuning))
    %{game | fields: gusted, events: Enum.reverse(events) ++ game.events}
  end

  defp send_gust({:gust, from}, fields, tuning) do
    Map.new(fields, fn
      {^from, field} -> {from, field}
      {id, field} -> {id, Field.gusted(field, tuning)}
    end)
  end

  defp send_gust(_event, fields, _tuning), do: fields

  @impl true
  def view(%__MODULE__{} = game, id) do
    %{
      me: Map.get(game.fields, id),
      rivals: for({other, field} <- game.fields, other != id, do: rival(field)),
      size: Field.size(),
      capacity: Cauldron.Tuning.get(game.tuning, :capacity)
    }
  end

  defp rival(field) do
    %{
      name: field.name,
      score: field.score,
      water: field.water,
      jars: Yoke.count(field.yoke),
      level: field.level,
      out?: field.out?,
      robot?: field.robot?
    }
  end

  @impl true
  def drain_events(%__MODULE__{events: events} = game),
    do: {Enum.reverse(events), %{game | events: []}}

  @doc "The outcome for the keeper of `view`: `nil` while they play, or the summary once they are out."
  @spec outcome(map()) :: map() | nil
  def outcome(%{me: %Field{out?: true} = me} = view) do
    best = Enum.max([me.score | Enum.map(view.rivals, & &1.score)])

    %{
      title: "The last jar breaks",
      lines: [
        "#{me.water} drops in the cistern, #{me.score} points",
        "storm #{me.best} at the most",
        if(me.score >= best,
          do: "the fullest cistern in the town",
          else: "the fullest held #{best}"
        )
      ],
      next: :same_world,
      score: me.score,
      water: me.water,
      best: me.best
    }
  end

  def outcome(_view), do: nil
end
