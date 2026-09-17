defmodule Cauldron2D.Grid.Path do
  @moduledoc """
  Ways across a tile grid: breadth-first for the fewest steps, A* for the cheapest.

      {:ok, path} = Cauldron2D.Grid.Path.find(&open?/1, {0, 0}, {5, 2}, size: {6, 5})
      {:ok, path} = Cauldron2D.Grid.Path.astar(&open?/1, {0, 0}, {5, 2}, size: {6, 5}, cost: &terrain/1)

  The grid is a function from a cell `{x, y}` to whether it can be walked. A path is the
  cells from the first step to the goal, the start left out; the same cell as start and
  goal is `[]`. `:none` is no way within the limit.

  ## Options

    * `:size` — `{width, height}` of the grid in cells. Required
    * `:wrap?` — whether the edges join. Default `false`
    * `:neighbours` — `:four` or `:eight`. Default `:four`
    * `:limit` — how many cells may be expanded before giving up. Default `10_000`
    * `:cost` — `astar/4` only: a function from a cell to the cost of stepping into it,
      a positive number. Default `1` everywhere
  """

  @type cell :: {integer(), integer()}
  @type passable :: (cell() -> boolean())

  @limit 10_000

  @doc "The way with the fewest steps."
  @spec find(passable(), cell(), cell(), keyword()) :: {:ok, [cell()]} | :none
  def find(passable?, from, to, opts) do
    grid = grid(passable?, opts)

    cond do
      from == to ->
        {:ok, []}

      not passable?.(to) ->
        :none

      true ->
        breadth(
          grid,
          :queue.from_list([from]),
          %{from => nil},
          to,
          Keyword.get(opts, :limit, @limit)
        )
    end
  end

  defp breadth(_grid, _queue, _seen, _goal, 0), do: :none

  defp breadth(grid, queue, seen, goal, limit) do
    case :queue.out(queue) do
      {:empty, _} ->
        :none

      {{:value, cell}, queue} ->
        next =
          for neighbour <- neighbours(grid, cell),
              grid.passable?.(neighbour),
              not Map.has_key?(seen, neighbour),
              do: neighbour

        if goal in next do
          {:ok, walk_back(Map.put(seen, goal, cell), goal)}
        else
          seen = Enum.reduce(next, seen, &Map.put(&2, &1, cell))
          breadth(grid, Enum.reduce(next, queue, &:queue.in/2), seen, goal, limit - 1)
        end
    end
  end

  @doc "The cheapest way, by `:cost`, guided by the distance still to go."
  @spec astar(passable(), cell(), cell(), keyword()) :: {:ok, [cell()]} | :none
  def astar(passable?, from, to, opts) do
    grid = grid(passable?, opts)
    cost = Keyword.get(opts, :cost, fn _cell -> 1 end)

    cond do
      from == to ->
        {:ok, []}

      not passable?.(to) ->
        :none

      true ->
        best_first(
          grid,
          cost,
          :gb_sets.singleton({heuristic(grid, from, to), 0, from}),
          %{from => {0, nil}},
          to,
          Keyword.get(opts, :limit, @limit)
        )
    end
  end

  defp best_first(_grid, _cost, _open, _seen, _goal, 0), do: :none

  defp best_first(grid, cost, open, seen, goal, limit) do
    case :gb_sets.is_empty(open) do
      true -> :none
      false -> expand(grid, cost, :gb_sets.take_smallest(open), seen, goal, limit)
    end
  end

  defp expand(_grid, _cost, {{_estimate, _so_far, goal}, _open}, seen, goal, _limit) do
    {:ok, walk_back(Map.new(seen, fn {cell, {_cost, previous}} -> {cell, previous} end), goal)}
  end

  defp expand(grid, cost, {{_estimate, so_far, cell}, open}, seen, goal, limit) do
    {open, seen} =
      for neighbour <- neighbours(grid, cell), grid.passable?.(neighbour), reduce: {open, seen} do
        acc -> consider(acc, grid, neighbour, so_far + cost.(neighbour), cell, goal)
      end

    best_first(grid, cost, open, seen, goal, limit - 1)
  end

  defp consider({open, seen} = acc, grid, neighbour, total, from, goal) do
    case Map.get(seen, neighbour) do
      {known, _} when known <= total ->
        acc

      _further_or_new ->
        {:gb_sets.add({total + heuristic(grid, neighbour, goal), total, neighbour}, open),
         Map.put(seen, neighbour, {total, from})}
    end
  end

  defp heuristic(grid, {x1, y1}, {x2, y2}) do
    dx = axis_distance(x1, x2, grid.width, grid.wrap?)
    dy = axis_distance(y1, y2, grid.height, grid.wrap?)
    if grid.neighbours == :eight, do: max(dx, dy), else: dx + dy
  end

  defp axis_distance(a, b, extent, true), do: min(abs(a - b), extent - abs(a - b))
  defp axis_distance(a, b, _extent, false), do: abs(a - b)

  defp walk_back(seen, cell, path \\ []) do
    case Map.fetch!(seen, cell) do
      nil -> path
      previous -> walk_back(seen, previous, [cell | path])
    end
  end

  defp grid(passable?, opts) do
    {width, height} = Keyword.fetch!(opts, :size)

    %{
      passable?: passable?,
      width: width,
      height: height,
      wrap?: Keyword.get(opts, :wrap?, false),
      neighbours: Keyword.get(opts, :neighbours, :four)
    }
  end

  @four [{1, 0}, {-1, 0}, {0, 1}, {0, -1}]
  @eight @four ++ [{1, 1}, {1, -1}, {-1, 1}, {-1, -1}]

  defp neighbours(grid, {x, y}) do
    steps = if grid.neighbours == :eight, do: @eight, else: @four

    for {dx, dy} <- steps, cell = shifted(grid, {x + dx, y + dy}), cell != nil, do: cell
  end

  defp shifted(%{wrap?: true} = grid, {x, y}),
    do: {Integer.mod(x, grid.width), Integer.mod(y, grid.height)}

  defp shifted(grid, {x, y}) when x >= 0 and y >= 0 and x < grid.width and y < grid.height,
    do: {x, y}

  defp shifted(_grid, _cell), do: nil
end
