defmodule Cauldron2D.Parallax.Strip do
  @moduledoc """
  A cell function over authored tiles, wrapping in one or both directions.

      rows = Cauldron2D.Parallax.Strip.legend(["..#..", "#####"], %{"#" => :brick, "." => :void})
      Cauldron2D.Parallax.Strip.cells(rows, wrap: :x)

  Row `0` of the tiles is tile row `0` of the layer. A coordinate outside the tiles on an
  axis that does not wrap is `:void`.
  """

  @type art :: term()
  @type cell :: :void | {art(), [art()], nil}
  @type wrap :: :both | :x | :y | :none

  @doc "Rows of cells from rows of characters, each character looked up in `legend`."
  @spec legend([String.t()], %{String.t() => art() | cell()}) :: [[cell()]]
  def legend(lines, legend) do
    for line <- lines do
      for character <- String.graphemes(line), do: cell(Map.fetch!(legend, character))
    end
  end

  @doc """
  Build the cell function over `rows`, a list of equal-length rows of cells.

  ## Options

    * `:wrap` — `:both`, `:x`, `:y` or `:none`. Default `:both`
  """
  @spec cells([[cell()]], keyword()) :: ({integer(), integer()} -> cell())
  def cells(rows, opts \\ [])

  def cells([], _opts), do: fn _coordinate -> :void end

  def cells(rows, opts) do
    height = length(rows)
    width = rows |> hd() |> length()
    wrap = Keyword.get(opts, :wrap, :both)

    tiles =
      for {row, y} <- Enum.with_index(rows),
          {cell, x} <- Enum.with_index(row),
          cell != :void,
          into: %{},
          do: {{x, y}, cell}

    fn {x, y} ->
      with {:ok, column} <- place(x, width, wrap in [:both, :x]),
           {:ok, line} <- place(y, height, wrap in [:both, :y]) do
        Map.get(tiles, {column, line}, :void)
      else
        :outside -> :void
      end
    end
  end

  defp place(value, extent, true), do: {:ok, Integer.mod(value, extent)}
  defp place(value, extent, false) when value >= 0 and value < extent, do: {:ok, value}
  defp place(_value, _extent, false), do: :outside

  defp cell(:void), do: :void
  defp cell({_art, overlays, _tint} = cell) when is_list(overlays), do: cell
  defp cell(art), do: {art, [], nil}
end
