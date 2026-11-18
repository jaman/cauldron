defmodule Cauldron.OpenWorld.Store do
  @moduledoc """
  Where a `Cauldron.OpenWorld.Map`'s cells are kept while they are not in the map.

  A store is `{module, config}`. `fetch/2` reads the cell at an address and `save/2`
  writes one; a store that only reads leaves `save/2` out.

      defmodule MyGame.Land do
        @behaviour Cauldron.OpenWorld.Store

        @impl true
        def fetch(seed, address), do: {:ok, MyGame.Land.made(seed, address)}
      end

      {:ok, cell} = Cauldron.OpenWorld.Store.fetch({MyGame.Land, 42}, {3, -1})

  Built in: `Cauldron.OpenWorld.Store.Memory` and `Cauldron.OpenWorld.Store.Files`.
  """

  alias Cauldron.OpenWorld.Cell

  @type t :: {module(), term()}

  @doc "The cell at `address`, `:none` where the store has no cell, or why it could not be read."
  @callback fetch(config :: term(), Cell.address()) :: {:ok, Cell.t()} | :none | {:error, term()}

  @doc "Keeps `cell`. Answers the store's config, changed if the store is a value."
  @callback save(config :: term(), Cell.t()) :: {:ok, term()} | {:error, term()}

  @optional_callbacks save: 2

  @doc "The cell at `address` in `store`."
  @spec fetch(t(), Cell.address()) :: {:ok, Cell.t()} | :none | {:error, term()}
  def fetch({module, config}, address), do: module.fetch(config, address)

  @doc "Keeps `cell` in `store` and answers the store as it is afterwards."
  @spec save(t(), Cell.t()) :: {:ok, t()} | {:error, term()}
  def save({module, config}, %Cell{} = cell) do
    with {:ok, config} <- module.save(config, cell), do: {:ok, {module, config}}
  end
end
