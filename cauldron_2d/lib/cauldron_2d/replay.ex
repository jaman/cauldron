defmodule Cauldron2D.Replay do
  @moduledoc """
  A record of everything that was done to a world, and the means to do it again.

  `Cauldron2D.World` started with `record: true` builds one; `Cauldron2D.World.replay/1`
  returns it. `run/4` rebuilds the game from its options and feeds the record back in,
  tick by tick, giving the same state the world reached.

      replay = Cauldron2D.World.replay(world)
      state = Cauldron2D.Replay.run(replay, MyGame, [seed: 7], 1 / 50)

  Entries are `{tick, action}` where `action` is `{:join, id, props}`, `{:leave, id}` or
  `{:input, id, input_state}`, and `tick` is how many steps had run when it happened.
  """

  @type action ::
          {:join, term(), map()} | {:leave, term()} | {:input, term(), Cauldron2D.Input.state()}
  @type t :: %__MODULE__{entries: [{non_neg_integer(), action()}], steps: non_neg_integer()}

  defstruct entries: [], steps: 0

  @doc "An empty record."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Add what happened at `tick`."
  @spec record(t(), non_neg_integer(), action()) :: t()
  def record(%__MODULE__{} = replay, tick, action) do
    %{replay | entries: [{tick, action} | replay.entries]}
  end

  @doc "Note that `steps` steps have run in total."
  @spec stepped(t(), non_neg_integer()) :: t()
  def stepped(%__MODULE__{} = replay, steps), do: %{replay | steps: steps}

  @doc "The entries oldest first."
  @spec entries(t()) :: [{non_neg_integer(), action()}]
  def entries(%__MODULE__{entries: entries}), do: Enum.reverse(entries)

  @doc "Rebuild `game` from `game_opts` and apply the record, stepping by `dt` each tick."
  @spec run(t(), module(), keyword(), float()) :: term()
  def run(%__MODULE__{} = replay, game, game_opts, dt) do
    by_tick = replay |> entries() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    stepped =
      Enum.reduce(0..(replay.steps - 1)//1, game.init(game_opts), fn tick, state ->
        state |> apply_tick(game, by_tick, tick) |> game.step(dt)
      end)

    apply_tick(stepped, game, by_tick, replay.steps)
  end

  defp apply_tick(state, game, by_tick, tick) do
    by_tick |> Map.get(tick, []) |> Enum.reduce(state, &apply_action(game, &1, &2))
  end

  defp apply_action(game, {:join, id, props}, state) do
    case game.join(state, id, props) do
      {:ok, joined} -> joined
      {:error, _reason} -> state
    end
  end

  defp apply_action(game, {:leave, id}, state), do: game.leave(state, id)
  defp apply_action(game, {:input, id, input}, state), do: game.handle_input(state, id, input)
end
