defmodule Cauldron2D.Drafter.Surface.Scale do
  @moduledoc """
  How a tile maps onto the terminal's pixels once the session knows the size of a cell.

  A tile is drawn at a whole multiple of its own pixels, or shrunk by a divisor of its
  size, whichever comes nearest to `zoom` rows of cells — so every image is sent at the
  size it is shown and the terminal scales nothing.

      scale = Cauldron2D.Drafter.Surface.Scale.new({14, 30}, 16, 1)
      scale.pixels
      #=> 32
  """

  @type factor :: {:magnify, pos_integer()} | {:reduce, pos_integer()}

  @type t :: %__MODULE__{
          cell: {pos_integer(), pos_integer()},
          tile: pos_integer(),
          factor: factor(),
          pixels: pos_integer()
        }

  @enforce_keys [:cell, :tile, :factor, :pixels]
  defstruct [:cell, :tile, :factor, :pixels]

  @doc """
  The scale for a terminal whose cells are `cell` pixels, an atlas whose tiles are `tile`
  pixels square, at `zoom` (`1` a tile the height of a row).
  """
  @spec new({pos_integer(), pos_integer()}, pos_integer(), number()) :: t()
  def new({_width, height} = cell, tile, zoom) do
    wanted = zoom * height

    case round(wanted / tile) do
      0 ->
        divisor = Enum.min_by(divisors(tile), &abs(&1 - tile / wanted))

        %__MODULE__{
          cell: cell,
          tile: tile,
          factor: {:reduce, divisor},
          pixels: div(tile, divisor)
        }

      times ->
        %__MODULE__{cell: cell, tile: tile, factor: {:magnify, times}, pixels: times * tile}
    end
  end

  @doc "The pane `rect` (in cells) in pixels."
  @spec pane(t(), map()) :: {pos_integer(), pos_integer()}
  def pane(%__MODULE__{cell: {width, height}}, rect),
    do: {max(1, rect.width) * width, max(1, rect.height) * height}

  @doc "How many tiles across and down the pane `rect` shows, fractional at the edges."
  @spec tiles(t(), map()) :: {float(), float()}
  def tiles(%__MODULE__{pixels: pixels} = scale, rect) do
    {width, height} = pane(scale, rect)
    {width / pixels, height / pixels}
  end

  @doc """
  Where a point `tiles` from the pane's top left falls: `{column, row, x_offset, y_offset}`,
  the cell and the pixels into it.
  """
  @spec place(t(), {number(), number()}) :: {integer(), integer(), integer(), integer()}
  def place(%__MODULE__{cell: {cell_width, cell_height}, pixels: pixels}, {x, y}) do
    {column, x_offset} = split(x * pixels, cell_width)
    {row, y_offset} = split(y * pixels, cell_height)
    {column, row, x_offset, y_offset}
  end

  @doc "A fraction of a tile as whole drawn pixels."
  @spec scroll(t(), {number(), number()}) :: {integer(), integer()}
  def scroll(%__MODULE__{pixels: pixels}, {x, y}), do: {round(x * pixels), round(y * pixels)}

  defp split(position, cell) do
    index = floor(position / cell)
    {index, round(position - index * cell)}
  end

  defp divisors(tile), do: for(divisor <- 1..tile, rem(tile, divisor) == 0, do: divisor)
end
