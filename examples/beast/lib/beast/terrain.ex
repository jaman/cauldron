defmodule Beast.Terrain do
  @moduledoc """
  The ground the runner crosses: flat turf with ledges, going on forever in both
  directions.

  `cell/1` answers for any tile. `floor_at/1` gives the world row a body standing at
  column `x` rests on.
  """

  import Bitwise

  @surface 16
  @mask 0xFFFFFFFFFFFFFFFF

  @doc "The world row the turf's surface sits on where there is no ledge."
  @spec surface() :: integer()
  def surface, do: @surface

  @doc "The cell at a tile, for `Cauldron2D.Camera`."
  @spec cell({integer(), integer()}) :: Cauldron2D.Surface.cell()
  def cell({x, y}) do
    floor = floor_at(x)

    cond do
      y > @surface -> {:dirt, [], nil}
      y == floor -> {:turf, [], nil}
      y > floor -> {:stone, [], nil}
      true -> :void
    end
  end

  @doc "The row a body standing at column `x` rests on."
  @spec floor_at(number()) :: integer()
  def floor_at(x) do
    column = floor(x)

    cond do
      ledge?(column, 23, 4) -> @surface - 2
      ledge?(column, 31, 3) -> @surface - 1
      true -> @surface
    end
  end

  @doc "Whether a tile is solid."
  @spec solid?({integer(), integer()}) :: boolean()
  def solid?({x, y}), do: y >= floor_at(x)

  defp ledge?(column, period, width) do
    place = Integer.mod(column, period)
    place < width and rem(scramble(div(column, period)), 3) == 0
  end

  defp scramble(value) do
    value = band(value * 0x9E3779B97F4A7C15, @mask)

    value
    |> bxor(bsr(value, 29))
    |> band(@mask)
  end
end
