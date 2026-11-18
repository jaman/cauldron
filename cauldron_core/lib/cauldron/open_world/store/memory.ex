defmodule Cauldron.OpenWorld.Store.Memory do
  @moduledoc """
  A `Cauldron.OpenWorld.Store` held as a value: its config is a map of cells by address.

      store = {Cauldron.OpenWorld.Store.Memory, %{}}
      {:ok, store} = Cauldron.OpenWorld.Store.save(store, cell)
  """

  @behaviour Cauldron.OpenWorld.Store

  alias Cauldron.OpenWorld.Cell

  @impl true
  def fetch(cells, address) do
    case Map.fetch(cells, address) do
      {:ok, cell} -> {:ok, cell}
      :error -> :none
    end
  end

  @impl true
  def save(cells, %Cell{address: address} = cell), do: {:ok, Map.put(cells, address, cell)}
end
