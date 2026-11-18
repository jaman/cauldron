defmodule Cistern.Game do
  @moduledoc """
  A town in drought, and a storm that will rain anywhere but the cistern. Every keeper —
  each player, each robot — has a square of their own, side by side, with their own
  Squall, all of them rained on from the same seed. A keeper carries a yoke of three
  jars, catches what the Squall lets go, and is out when the last jar breaks; the rules
  of one square are `Cistern.Field`'s.

  This is a `Cauldron.Game`: `init/1` builds it, `join/3` gives a keeper a square,
  `step/2` moves every square by `dt` seconds, `view/2` is one keeper's square and how
  the others are doing, and `drain_events/1` is what happened since it was last asked.
  Nothing here reads a clock or draws.

  ## Options

    * `:seed` — the generator's seed, so a game replays the same. Default: fresh
    * `:tuning` — overrides on `Cistern.Tuning`'s defaults
  """

  @behaviour Cauldron.Game

  alias Cauldron.{Rng, Tuning}
  alias Cistern.Field
  alias Cistern.Tuning, as: Settings

  @apart 100

  @type t :: %__MODULE__{
          fields: %{term() => Field.t()},
          seed: integer(),
          tuning: Tuning.t(),
          seats: non_neg_integer(),
          events: [term()]
        }

  defstruct fields: %{}, seed: 0, tuning: nil, seats: 0, events: []

  @impl true
  def init(opts) do
    seed =
      case Keyword.get(opts, :seed) do
        nil -> Rng.random() |> elem(1)
        seed -> seed
      end

    %__MODULE__{seed: seed, tuning: Settings.new(Keyword.get(opts, :tuning, []))}
  end

  @impl true
  def join(%__MODULE__{} = game, id, props) do
    field =
      Field.new(id, Map.get(props, :username, "keeper"), game.seed,
        robot?: Map.get(props, :robot?, false),
        offset: game.seats * @apart,
        lull: Tuning.get(game.tuning, :lull)
      )

    {:ok, %{game | fields: Map.put(game.fields, id, field), seats: game.seats + 1}}
  end

  @impl true
  def leave(%__MODULE__{} = game, id), do: %{game | fields: Map.delete(game.fields, id)}

  @impl true
  def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
    case Map.fetch(game.fields, id) do
      {:ok, field} ->
        %{game | fields: Map.put(game.fields, id, Field.hold(field, held, Map.get(input, :aim)))}

      :error ->
        game
    end
  end

  @impl true
  def step(%__MODULE__{} = game, dt) do
    Enum.reduce(game.fields, game, fn {id, field}, acc ->
      {stepped, events} = Field.step(field, dt, acc.tuning)

      %{
        acc
        | fields: Map.put(acc.fields, id, stepped),
          events: Enum.reverse(events) ++ acc.events
      }
    end)
  end

  @impl true
  def view(%__MODULE__{} = game, id) do
    %{
      me: Map.get(game.fields, id),
      rivals:
        for {other, field} <- game.fields, other != id do
          %{
            name: field.name,
            score: field.score,
            jars: Field.jar_count(field),
            level: field.level,
            out?: field.out?,
            robot?: field.robot?
          }
        end,
      size: Field.size()
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
        "#{me.caught} drops in the cistern, #{me.score} points",
        "storm #{me.best} at the most",
        if(me.score >= best,
          do: "the fullest cistern in the town",
          else: "the fullest held #{best}"
        )
      ],
      next: :same_world
    }
  end

  def outcome(_view), do: nil
end
