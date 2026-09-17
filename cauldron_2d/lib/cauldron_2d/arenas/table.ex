defmodule Cauldron2D.Arenas.Table do
  @moduledoc """
  The registered arenas, one record each, in an ETS table this process owns.

      Cauldron2D.Arenas.Table.put(:pit, %{id: :pit, opts: [game: MyGame], listing: %{name: "The Pit"}})
      Cauldron2D.Arenas.Table.all()
      Cauldron2D.Arenas.Table.listings()

  A record's `listing` is kept beside it so `listings/0` reads the listings alone,
  leaving the records — a game's options can be large — where they are.
  """

  use GenServer

  @table __MODULE__

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Record arena `id`; `record.listing`, when there is one, is what `listings/0` returns for it."
  @spec put(term(), map()) :: :ok
  def put(id, record) do
    :ets.insert(@table, {id, record, Map.get(record, :listing, %{})})
    :ok
  end

  @doc "The record of arena `id`, or `nil`."
  @spec get(term()) :: map() | nil
  def get(id) do
    case :ets.lookup(@table, id) do
      [{_id, record, _listing}] -> record
      [] -> nil
    end
  end

  @doc "Every arena's record."
  @spec all() :: [map()]
  def all, do: for({_id, record, _listing} <- :ets.tab2list(@table), do: record)

  @doc "Every arena's id with its listing, copying nothing else of the records."
  @spec listings() :: [{term(), map()}]
  def listings, do: :ets.select(@table, [{{:"$1", :_, :"$2"}, [], [{{:"$1", :"$2"}}]}])

  @doc "Forget arena `id`."
  @spec delete(term()) :: :ok
  def delete(id) do
    :ets.delete(@table, id)
    :ok
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end
end
