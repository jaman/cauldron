defmodule Cauldron.OpenWorld.Store.Files do
  @moduledoc """
  A `Cauldron.OpenWorld.Store` in a directory, one file a cell, named
  `<column>_<row>.cell`. Its config is the directory's path.

      store = {Cauldron.OpenWorld.Store.Files, "priv/land"}
      {:ok, cell} = Cauldron.OpenWorld.Store.fetch(store, {0, 0})
  """

  @behaviour Cauldron.OpenWorld.Store

  alias Cauldron.OpenWorld.Cell

  @impl true
  def fetch(directory, address) do
    case File.read(path(directory, address)) do
      {:ok, bytes} -> read(bytes)
      {:error, :enoent} -> :none
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def save(directory, %Cell{address: address} = cell) do
    with :ok <- File.mkdir_p(directory),
         :ok <- File.write(path(directory, address), :erlang.term_to_binary(cell, [:compressed])) do
      {:ok, directory}
    end
  end

  defp path(directory, {column, row}), do: Path.join(directory, "#{column}_#{row}.cell")

  defp read(bytes) do
    case :erlang.binary_to_term(bytes, [:safe]) do
      %Cell{} = cell -> {:ok, cell}
      _other -> {:error, :not_a_cell}
    end
  rescue
    ArgumentError -> {:error, :not_a_cell}
  end
end
