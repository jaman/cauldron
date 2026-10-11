defmodule Cauldron2D.Grid.Coarse do
  @moduledoc """
  Ways across a tile grid of any size, for bodies that move through the open tiles.

      coarse = Cauldron2D.Grid.Coarse.new(grid, {width, height}, wrap?: true)
      {:ok, path} = Cauldron2D.Grid.Coarse.find(coarse, me.pos, enemy.pos)
      goal = Cauldron2D.Grid.Coarse.waypoint(grid, me.pos, path, radius)

  `grid` is the function `Cauldron2D.Collision` takes, a tile coordinate to `:open`,
  `:solid` or a half tile; a tile is open when it reads `:open`. `new/3` cuts the grid
  into blocks of `:block` tiles a side (default 8) and joins the open tiles of each
  block that touch edge to edge into regions (`Cauldron2D.Grid.Coarse.Regions`). `find/4`
  searches the regions for the order to cross them, then the tiles of the first few for
  the steps, so a search costs what the regions crossed cost, whatever the grid's size,
  and finds a way whenever there is one.

  A step goes to one of the eight tiles around, diagonally only where both tiles beside
  the corner are open, and crossing a tile beside one that is not open costs three times
  as much as crossing one in the open, so ways keep off walls where there is room.

  A point on a tile that is not open — in the open half of a half tile — starts from, or
  is sought at, the open tile around it nearest the point.

  On a wrapping grid a path runs on across the edges instead of jumping back: each
  point is placed nearest the one before it, the first nearest `from`, so points may lie
  off the grid. `Cauldron2D.Grid.Coarse.Space.near/3` places any position nearest
  another the same way.
  """

  alias Cauldron2D.Collision
  alias Cauldron2D.Grid.Coarse.{Regions, Search, Space}

  @type point :: {number(), number()}

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          wrap?: boolean(),
          block: pos_integer(),
          labels: binary(),
          spots: tuple(),
          links: tuple(),
          components: tuple()
        }

  @enforce_keys [:width, :height, :wrap?, :block, :labels, :spots, :links, :components]
  defstruct @enforce_keys

  @block 8
  @ahead 3
  @sight 16
  @cramped 3.0
  @diagonal :math.sqrt(2)
  @edges [{1, 0}, {-1, 0}, {0, 1}, {0, -1}]
  @around @edges ++ [{1, 1}, {1, -1}, {-1, 1}, {-1, -1}]

  @doc "The regions of `grid`, `size` tiles across and down; options `:block`, tiles to a block side (default #{@block}), and `:wrap?` (default false)."
  @spec new(Collision.grid(), {pos_integer(), pos_integer()}, keyword()) :: t()
  def new(grid, {width, height}, opts \\ []) do
    space = %{width: width, height: height, wrap?: Keyword.get(opts, :wrap?, false)}
    block = Keyword.get(opts, :block, @block)
    regions = Regions.build(&(grid.(&1) == :open), space, block)

    struct!(
      __MODULE__,
      space
      |> Map.put(:block, block)
      |> Map.merge(Map.take(regions, [:labels, :spots, :links, :components]))
    )
  end

  @doc """
  The way from `from` to `to` as the points to pass, as the module documentation places
  them, ending at `to` itself when it lies within the regions searched; `{:ok, [to]}` when
  both are on one tile. `:none` when either is on no open tile or no way joins them.

  Option `:ahead`: how many regions past the one `from` is in the steps run through
  (default #{@ahead}). A way crossing more ends where the last of them meets the next.
  """
  @spec find(t(), point(), point(), keyword()) :: {:ok, [point()]} | :none
  def find(%__MODULE__{} = coarse, from, to, opts \\ []) do
    ahead = Keyword.get(opts, :ahead, @ahead)

    with {:ok, start} <- open_near(coarse, from),
         {:ok, goal} <- open_near(coarse, to),
         :ok <- joined(coarse, start, goal),
         {:ok, regions} <- regions(coarse, start, goal),
         {:ok, [_start | tiles]} <- tiles(coarse, start, goal, regions, ahead) do
      {:ok, points(coarse, from, to, goal, tiles)}
    end
  end

  @doc "Whether any way joins `from` and `to`, each on an open tile or beside one."
  @spec reachable?(t(), point(), point()) :: boolean()
  def reachable?(%__MODULE__{} = coarse, from, to) do
    with {:ok, start} <- open_near(coarse, from),
         {:ok, goal} <- open_near(coarse, to) do
      joined(coarse, start, goal) == :ok
    else
      :none -> false
    end
  end

  @doc "A point in the middle of every region, one a region: places spread over all the open parts of the grid."
  @spec spots(t()) :: [point()]
  def spots(%__MODULE__{spots: spots}), do: for(tile <- Tuple.to_list(spots), do: centre(tile))

  @doc """
  The point of `path` to make for from `from`: of its first #{@sight}, the last a body of
  `radius` reaches in a clear straight line from `from` with every one before it reached
  the same way, else the first.
  """
  @spec waypoint(Collision.grid(), point(), [point(), ...], number()) :: point()
  def waypoint(grid, from, [first | _] = path, radius \\ 0.0) do
    path
    |> Enum.take(@sight)
    |> Enum.take_while(&match?({:clear, _}, Collision.sweep(grid, from, &1, radius)))
    |> List.last(first)
  end

  defp open_near(coarse, point) do
    case Space.tile(coarse, point) do
      nil -> :none
      tile -> if open?(coarse, tile), do: {:ok, tile}, else: open_around(coarse, point, tile)
    end
  end

  defp open_around(coarse, point, {x, y}) do
    nearest =
      @around
      |> Enum.map(fn {dx, dy} -> Space.tile(coarse, {x + dx, y + dy}) end)
      |> Enum.filter(&(&1 != nil and open?(coarse, &1)))
      |> Enum.min_by(&Space.distance(coarse, point, centre(&1)), fn -> nil end)

    if nearest, do: {:ok, nearest}, else: :none
  end

  defp joined(coarse, start, goal) do
    if component(coarse, start) == component(coarse, goal), do: :ok, else: :none
  end

  defp component(coarse, tile), do: elem(coarse.components, region_at(coarse, tile) - 1)

  defp regions(coarse, start, goal) do
    last = region_at(coarse, goal)

    Search.run(
      region_at(coarse, start),
      &(&1 == last),
      &elem(coarse.links, &1 - 1),
      &Space.distance(coarse, elem(coarse.spots, &1 - 1), goal)
    )
  end

  defp tiles(coarse, start, goal, regions, ahead) do
    case Enum.split(regions, ahead + 1) do
      {within, []} ->
        Search.run(
          start,
          &(&1 == goal),
          &steps(coarse, MapSet.new(within), &1),
          &Space.distance(coarse, &1, goal)
        )

      {within, [next | _further]} ->
        last = List.last(within)
        beyond = elem(coarse.spots, next - 1)

        Search.run(
          start,
          &leaving?(coarse, &1, last, next),
          &steps(coarse, MapSet.new(within), &1),
          &Space.distance(coarse, &1, beyond)
        )
    end
  end

  defp leaving?(coarse, {x, y} = tile, last, next) do
    region_at(coarse, tile) == last and
      Enum.any?(@edges, fn {dx, dy} -> region_at(coarse, {x + dx, y + dy}) == next end)
  end

  defp steps(coarse, inside, {x, y} = tile) do
    for {dx, dy} <- @around,
        next = Space.tile(coarse, {x + dx, y + dy}),
        MapSet.member?(inside, region_at(coarse, next)),
        corner_open?(coarse, tile, {dx, dy}),
        do: {next, step_cost(coarse, next, {dx, dy})}
  end

  defp corner_open?(_coarse, _tile, {0, _dy}), do: true
  defp corner_open?(_coarse, _tile, {_dx, 0}), do: true

  defp corner_open?(coarse, {x, y}, {dx, dy}),
    do: open?(coarse, {x + dx, y}) and open?(coarse, {x, y + dy})

  defp step_cost(coarse, tile, {dx, dy}) do
    length = if dx != 0 and dy != 0, do: @diagonal, else: 1.0
    if cramped?(coarse, tile), do: length * @cramped, else: length
  end

  defp cramped?(coarse, {x, y}),
    do: Enum.any?(@around, fn {dx, dy} -> not open?(coarse, {x + dx, y + dy}) end)

  defp points(coarse, from, to, _goal, []), do: [Space.near(coarse, from, to)]

  defp points(coarse, {fx, fy}, to, goal, tiles) do
    {placed, _last} =
      Enum.map_reduce(tiles, {floor(fx), floor(fy)}, fn tile, previous ->
        here = Space.near(coarse, previous, tile)
        {here, here}
      end)

    centres = Enum.map(placed, &centre/1)

    if List.last(tiles) == goal,
      do: List.replace_at(centres, -1, Space.near(coarse, List.last(centres), to)),
      else: centres
  end

  defp centre({x, y}), do: {x + 0.5, y + 0.5}

  defp open?(coarse, tile), do: region_at(coarse, tile) != 0

  defp region_at(coarse, tile) do
    case Space.tile(coarse, tile) do
      nil -> 0
      {x, y} -> label(coarse.labels, (y * coarse.width + x) * 4)
    end
  end

  defp label(labels, offset) do
    <<_before::binary-size(^offset), region::32, _after::binary>> = labels
    region
  end
end
