defmodule Cauldron2D.Atlas.Tables do
  @moduledoc """
  Owns every atlas's composited-tile cache table, so a table outlives whichever process
  installed the atlas.

      Cauldron2D.Atlas.Tables.ensure(Cauldron2D.Atlas.cache(:my_game))

  Started by the `:cauldron_2d` application. `ensure/1` makes the named table, public
  and read-concurrent, if it does not exist, and returns its name either way.
  """

  use GenServer

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "The table named `name`, made by this process if it is not there."
  @spec ensure(atom()) :: atom()
  def ensure(name) when is_atom(name) do
    case :ets.whereis(name) do
      :undefined -> GenServer.call(__MODULE__, {:ensure, name})
      _existing -> name
    end
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:ensure, name}, _from, state) do
    if :ets.whereis(name) == :undefined do
      :ets.new(name, [:named_table, :public, :set, read_concurrency: true])
    end

    {:reply, name, state}
  end
end
