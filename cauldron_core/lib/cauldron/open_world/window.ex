defmodule Cauldron.OpenWorld.Window do
  @moduledoc """
  Which cells of a `Cauldron.OpenWorld.Map` to hold while viewers move over it, so cells
  come and go around them without a zone ever being loaded whole.

      held = MapSet.new()
      %{load: load, drop: drop, held: held} =
        Cauldron.OpenWorld.Window.step(held, map, [{130.0, 40.0}], load: 200.0, keep: 260.0)

  `load` lists the addresses to fetch, nearest first, `drop` those to let go, and `held`
  is what is held once both are done. A cell is wanted when any part of it is within
  `:load` of a viewer and is kept until every part of it is farther than `:keep` from
  all of them.

  `levels/4` sorts held cells by distance into detail levels, for drawing far cells
  coarser.
  """

  alias Cauldron.OpenWorld.Cell
  alias Cauldron.OpenWorld.Map, as: World

  @type addresses :: MapSet.t(Cell.address())

  @doc "The addresses of every cell with a part within `radius` of one of `points`."
  @spec wanted(World.t(), [World.point()], number()) :: addresses()
  def wanted(%World{} = map, points, radius) do
    for {x, y} = point <- points,
        {low_column, low_row} = World.address(map, {x - radius, y - radius}),
        {high_column, high_row} = World.address(map, {x + radius, y + radius}),
        column <- low_column..high_column,
        row <- low_row..high_row,
        distance(map, {column, row}, point) <= radius,
        into: MapSet.new(),
        do: {column, row}
  end

  @doc "What to load and drop for viewers at `points`, given the addresses `held` now."
  @spec step(addresses(), World.t(), [World.point()], keyword()) ::
          %{load: [Cell.address()], drop: [Cell.address()], held: addresses()}
  def step(held, %World{} = map, points, opts) do
    load_radius = Keyword.fetch!(opts, :load)
    near = wanted(map, points, load_radius)
    kept = wanted(map, points, Keyword.get(opts, :keep, load_radius))
    drop = MapSet.difference(held, kept)

    load =
      near
      |> MapSet.difference(held)
      |> Enum.sort_by(&nearest(map, &1, points))

    %{
      load: load,
      drop: MapSet.to_list(drop),
      held: held |> MapSet.difference(drop) |> MapSet.union(near)
    }
  end

  @doc """
  The detail level of each of `addresses`: how many of `distances` (ascending) its
  nearest part is beyond, from the nearest of `points`. Level 0 is the finest.
  """
  @spec levels(World.t(), Enumerable.t(Cell.address()), [World.point()], [number()]) ::
          %{Cell.address() => non_neg_integer()}
  def levels(%World{} = map, addresses, points, distances) do
    Map.new(addresses, fn address ->
      away = nearest(map, address, points)
      {address, Enum.count(distances, &(away > &1))}
    end)
  end

  @doc "How far `point` is from the nearest part of the cell at `address`; 0 inside it."
  @spec distance(World.t(), Cell.address(), World.point()) :: float()
  def distance(%World{cell_size: size} = map, address, {x, y}) do
    {low_x, low_y} = World.origin(map, address)
    off_x = x - (x |> max(low_x) |> min(low_x + size))
    off_y = y - (y |> max(low_y) |> min(low_y + size))
    :math.sqrt(off_x * off_x + off_y * off_y)
  end

  defp nearest(map, address, points),
    do: points |> Enum.map(&distance(map, address, &1)) |> Enum.min(fn -> 0.0 end)
end
