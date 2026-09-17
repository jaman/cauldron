defmodule Cauldron2D.Grid.Coarse do
  @moduledoc """
  A tile grid in blocks, for finding a way when the tiles are many: a block is passable
  when every tile in it is open, and a path is a run of block centres.

      coarse = Cauldron2D.Grid.Coarse.new(grid, {width, height}, block: 2, wrap?: true)
      {:ok, path} = Cauldron2D.Grid.Coarse.find(coarse, me.pos, enemy.pos)
      goal = Cauldron2D.Grid.Coarse.waypoint(grid, me.pos, path)

  `grid` is the function `Cauldron2D.Collision` takes, a tile coordinate to `:open`,
  `:solid` or a half tile. A point in a block that is not passable — on a base, in a
  pocket — starts from, or is sought at, the nearest passable block within two of it.
  """

  alias Cauldron2D.Collision
  alias Cauldron2D.Grid.Path

  @type t :: %__MODULE__{
          passable: MapSet.t({integer(), integer()}),
          width: pos_integer(),
          height: pos_integer(),
          block: pos_integer(),
          wrap?: boolean()
        }

  defstruct passable: MapSet.new(), width: 1, height: 1, block: 2, wrap?: false

  @block 2
  @limit 400

  @doc "The coarse map of `grid`, `size` tiles across and down; options `:block`, tiles to a block (default #{@block}), and `:wrap?` (default false)."
  @spec new(Collision.grid(), {pos_integer(), pos_integer()}, keyword()) :: t()
  def new(grid, {width, height}, opts \\ []) do
    block = Keyword.get(opts, :block, @block)
    across = ceil_div(width, block)
    down = ceil_div(height, block)

    passable =
      for bx <- 0..(across - 1),
          by <- 0..(down - 1),
          open_block?(grid, {bx, by}, block, {width, height}),
          into: MapSet.new(),
          do: {bx, by}

    %__MODULE__{
      passable: passable,
      width: across,
      height: down,
      block: block,
      wrap?: Keyword.get(opts, :wrap?, false)
    }
  end

  @doc "Whether the block holding the tile at `point` is passable."
  @spec passable?(t(), {number(), number()}) :: boolean()
  def passable?(%__MODULE__{} = coarse, point),
    do: MapSet.member?(coarse.passable, block_of(coarse, point))

  @doc "The path from `from` to `to` as block centres, or `:none` when there is none within `limit` blocks."
  @spec find(t(), {number(), number()}, {number(), number()}, pos_integer()) ::
          {:ok, [{float(), float()}]} | :none
  def find(%__MODULE__{} = coarse, from, to, limit \\ @limit) do
    with {:ok, start} <- nearest_passable(coarse, block_of(coarse, from)),
         {:ok, goal} <- nearest_passable(coarse, block_of(coarse, to)),
         {:ok, blocks} <- blocks(coarse, start, goal, limit) do
      {:ok, Enum.map(blocks, &centre(coarse, &1))}
    end
  end

  defp blocks(_coarse, goal, goal, _limit), do: {:ok, [goal]}

  defp blocks(coarse, start, goal, limit) do
    Path.find(&MapSet.member?(coarse.passable, &1), start, goal,
      size: {coarse.width, coarse.height},
      wrap?: coarse.wrap?,
      limit: limit
    )
  end

  defp nearest_passable(coarse, block) do
    if MapSet.member?(coarse.passable, block),
      do: {:ok, block},
      else: nearest_around(coarse, block)
  end

  defp nearest_around(coarse, block) do
    near =
      for dx <- -2..2,
          dy <- -2..2,
          {dx, dy} != {0, 0},
          candidate = shifted(coarse, block, {dx, dy}),
          MapSet.member?(coarse.passable, candidate),
          do: {abs(dx) + abs(dy), candidate}

    case Enum.min(near, fn -> nil end) do
      nil -> :none
      {_distance, candidate} -> {:ok, candidate}
    end
  end

  defp shifted(%{wrap?: true} = coarse, {x, y}, {dx, dy}),
    do: {Integer.mod(x + dx, coarse.width), Integer.mod(y + dy, coarse.height)}

  defp shifted(coarse, {x, y}, {dx, dy}) do
    if x + dx >= 0 and y + dy >= 0 and x + dx < coarse.width and y + dy < coarse.height,
      do: {x + dx, y + dy}
  end

  @doc "The point of `path` to make for from `from`: the furthest in a clear straight line on `grid`, else the first."
  @spec waypoint(Collision.grid(), {number(), number()}, [{float(), float()}]) ::
          {float(), float()}
  def waypoint(grid, from, path) do
    path
    |> Enum.reverse()
    |> Enum.find(hd(path), &match?({:clear, _}, Collision.sweep(grid, from, &1, 0.0)))
  end

  @doc "The block the tile at `point` is in."
  @spec block_of(t(), {number(), number()}) :: {integer(), integer()}
  def block_of(%__MODULE__{} = coarse, {x, y}),
    do:
      {Integer.mod(div(trunc(x), coarse.block), coarse.width),
       Integer.mod(div(trunc(y), coarse.block), coarse.height)}

  @doc "The tile position at the centre of a block."
  @spec centre(t(), {integer(), integer()}) :: {float(), float()}
  def centre(%__MODULE__{} = coarse, {bx, by}),
    do: {bx * coarse.block + coarse.block / 2, by * coarse.block + coarse.block / 2}

  defp open_block?(grid, {bx, by}, block, {width, height}) do
    Enum.all?(
      for(
        x <- (bx * block)..min(bx * block + block - 1, width - 1),
        y <- (by * block)..min(by * block + block - 1, height - 1),
        do: {x, y}
      ),
      &(grid.(&1) == :open)
    )
  end

  defp ceil_div(a, b), do: div(a + b - 1, b)
end
