defmodule Cauldron2D.Thinkers do
  @moduledoc """
  The things in a world that change by themselves each tick — a door closing, a lift
  waiting, a light flickering, a creature — kept in a fixed order so a world run twice
  from the same start runs the same.

      thinkers = Cauldron2D.Thinkers.new()
      {door, thinkers} = Cauldron2D.Thinkers.add(thinkers, %{kind: :door, sector: 12, speed: 2.0})

      {thinkers, world} =
        Cauldron2D.Thinkers.run(thinkers, world, fn thinker, id, world ->
          MyGame.think(thinker, id, world)
        end)

  A thinker is any term, filed under the id `add/2` gives it. `run/3` calls the function
  for each thinker in the order they were added; it answers `{:keep, thinker, world}` to
  carry on or `{:done, world}` to be removed. A run visits the thinkers that existed when
  it began; thinkers to start during a run are added with `add/2` to the thinkers it
  returns.
  """

  @enforce_keys [:next, :entries]
  defstruct [:next, :entries]

  @type id :: pos_integer()
  @type t :: %__MODULE__{next: pos_integer(), entries: :gb_trees.tree(id(), term())}

  @doc "No thinkers."
  @spec new() :: t()
  def new, do: %__MODULE__{next: 1, entries: :gb_trees.empty()}

  @doc "Add `thinker`; gives its id and the thinkers."
  @spec add(t(), term()) :: {id(), t()}
  def add(%__MODULE__{} = thinkers, thinker) do
    id = thinkers.next
    {id, %{thinkers | next: id + 1, entries: :gb_trees.insert(id, thinker, thinkers.entries)}}
  end

  @doc "Remove thinker `id`, if it is there."
  @spec remove(t(), id()) :: t()
  def remove(%__MODULE__{} = thinkers, id),
    do: %{thinkers | entries: :gb_trees.delete_any(id, thinkers.entries)}

  @doc "Thinker `id`, or `nil`."
  @spec get(t(), id()) :: term() | nil
  def get(%__MODULE__{entries: entries}, id) do
    case :gb_trees.lookup(id, entries) do
      {:value, thinker} -> thinker
      :none -> nil
    end
  end

  @doc "Replace thinker `id` with `fun.(thinker)`; nothing if it is not there."
  @spec update(t(), id(), (term() -> term())) :: t()
  def update(%__MODULE__{} = thinkers, id, fun) do
    case :gb_trees.lookup(id, thinkers.entries) do
      {:value, thinker} ->
        %{thinkers | entries: :gb_trees.update(id, fun.(thinker), thinkers.entries)}

      :none ->
        thinkers
    end
  end

  @doc "Every thinker with its id, in order."
  @spec to_list(t()) :: [{id(), term()}]
  def to_list(%__MODULE__{entries: entries}), do: :gb_trees.to_list(entries)

  @doc "How many thinkers there are."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{entries: entries}), do: :gb_trees.size(entries)

  @doc "Run every thinker once, in order. See the moduledoc."
  @spec run(t(), world, (term(), id(), world -> {:keep, term(), world} | {:done, world})) ::
          {t(), world}
        when world: term()
  def run(%__MODULE__{} = thinkers, world, fun) do
    Enum.reduce(to_list(thinkers), {thinkers, world}, fn {id, thinker}, {acc, current} ->
      case fun.(thinker, id, current) do
        {:keep, thinker, current} ->
          {%{acc | entries: :gb_trees.enter(id, thinker, acc.entries)}, current}

        {:done, current} ->
          {remove(acc, id), current}
      end
    end)
  end
end
