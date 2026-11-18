defmodule Cauldron.OpenWorld.Map do
  @moduledoc """
  A world without zones: square cells laid edge to edge, put in and taken out one at a
  time, with the ground, water and things each holds.

  Points are `{x, y}` on the ground plane and heights are a third number, so a game seen
  from above and a game in three dimensions read the same map. A cell is `cell_size`
  wide and carries `samples` steps of ground height a side
  (`Cauldron.OpenWorld.Cell`). Between its samples the ground follows the two triangles
  of each grid square, split from the square's `{x + 1, y}` corner to its `{x, y + 1}`
  corner.

  A cell's role says how far the simulation reaches: movers enter `:simulated` cells,
  `:shown` cells are only drawn, and where the map holds no cell there is nothing. What
  stops a mover at the end of the simulated cells is the map's `edges`
  (`Cauldron.OpenWorld.Edge`), asked in order by `travel/3`. Its `panels`
  (`Cauldron.OpenWorld.Panel`) are standing pictures of what lies beyond.

      map =
        Cauldron.OpenWorld.Map.new(
          cell_size: 64.0,
          samples: 64,
          edges: [{Cauldron.OpenWorld.Edge.Scenery, margin: 1.0}]
        )

      map = Cauldron.OpenWorld.Map.put(map, cell)
      Cauldron.OpenWorld.Map.height(map, {10.0, 20.0})
      {point, stopped_by} = Cauldron.OpenWorld.Map.travel(map, {10.0, 20.0}, {10.0, 70.0})
  """

  alias Cauldron.OpenWorld.{Cell, Panel, Thing}

  @type point :: {float(), float()}
  @type t :: %__MODULE__{
          cell_size: float(),
          samples: pos_integer(),
          cells: %{Cell.address() => Cell.t()},
          edges: [{module(), keyword()}],
          panels: [Panel.t()]
        }

  @enforce_keys [:cell_size, :samples]
  defstruct [:cell_size, :samples, cells: %{}, edges: [], panels: []]

  @doc "An empty map. Options: `:cell_size`, `:samples`, `:edges`, `:panels`."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      cell_size: Keyword.fetch!(opts, :cell_size) / 1,
      samples: Keyword.fetch!(opts, :samples),
      edges: Keyword.get(opts, :edges, []),
      panels: Keyword.get(opts, :panels, [])
    }
  end

  @doc "The map with `cell` in it, in place of any cell at the same address."
  @spec put(t(), Cell.t()) :: t()
  def put(%__MODULE__{cells: cells} = map, %Cell{address: address} = cell),
    do: %{map | cells: Map.put(cells, address, cell)}

  @doc "The map without the cell at `address`."
  @spec drop(t(), Cell.address()) :: t()
  def drop(%__MODULE__{cells: cells} = map, address), do: %{map | cells: Map.delete(cells, address)}

  @doc "The cell at `address`, or `nil`."
  @spec cell(t(), Cell.address()) :: Cell.t() | nil
  def cell(%__MODULE__{cells: cells}, address), do: Map.get(cells, address)

  @doc "The address of the cell `point` lies in."
  @spec address(t(), point()) :: Cell.address()
  def address(%__MODULE__{cell_size: size}, {x, y}), do: {floor(x / size), floor(y / size)}

  @doc "The low corner of the cell at `address`."
  @spec origin(t(), Cell.address()) :: point()
  def origin(%__MODULE__{cell_size: size}, {column, row}), do: {column * size, row * size}

  @doc "The role of the cell `point` lies in, or `nil` where the map holds none."
  @spec role(t(), point()) :: Cell.role() | nil
  def role(%__MODULE__{} = map, point) do
    case cell(map, address(map, point)) do
      %Cell{role: role} -> role
      nil -> nil
    end
  end

  @doc "Whether `point` lies in a simulated cell."
  @spec simulated?(t(), point()) :: boolean()
  def simulated?(%__MODULE__{} = map, point), do: role(map, point) == :simulated

  @doc "The ground's height at `point`, or `nil` where the map holds no cell."
  @spec height(t(), point()) :: float() | nil
  def height(%__MODULE__{} = map, point) do
    with {cell, across, along, right, up} <- square(map, point) do
      corners = corners(cell, map.samples, across, along)
      on_triangle(corners, right, up)
    end
  end

  @doc """
  How steeply the ground rises at `point`: `{rise_along_x, rise_along_y}`, height gained
  for each unit travelled; `nil` where the map holds no cell.
  """
  @spec slope(t(), point()) :: {float(), float()} | nil
  def slope(%__MODULE__{} = map, point) do
    with {cell, across, along, right, up} <- square(map, point) do
      step = map.cell_size / map.samples
      rise(corners(cell, map.samples, across, along), right, up, step)
    end
  end

  @doc """
  How much of each of the four kinds of ground is at the sample nearest `point`, 0 to
  255 each; `nil` where the map holds no cell or the cell has no kinds.
  """
  @spec kind(t(), point()) :: {0..255, 0..255, 0..255, 0..255} | nil
  def kind(%__MODULE__{samples: samples} = map, point) do
    with {cell, across, along, right, up} <- square(map, point) do
      Cell.kind(cell, samples, across + round(right), along + round(up))
    end
  end

  @doc "The height of the water's surface over `point`, or `nil` where there is none."
  @spec water(t(), point()) :: float() | nil
  def water(%__MODULE__{} = map, point) do
    case cell(map, address(map, point)) do
      %Cell{water: water} -> water
      nil -> nil
    end
  end

  @doc "The things whose position is within `radius` of `point`."
  @spec things(t(), point(), number()) :: [Thing.t()]
  def things(%__MODULE__{} = map, {x, y}, radius) do
    {low_column, low_row} = address(map, {x - radius, y - radius})
    {high_column, high_row} = address(map, {x + radius, y + radius})

    for column <- low_column..high_column,
        row <- low_row..high_row,
        %Cell{things: things} <- [cell(map, {column, row})],
        %Thing{position: {tx, ty}} = thing <- things,
        (tx - x) * (tx - x) + (ty - y) * (ty - y) <= radius * radius,
        do: thing
  end

  @doc """
  Where a move from `from` to `to` ends once every edge has been asked, and the edge
  modules that stopped it, first asked first.
  """
  @spec travel(t(), point(), point()) :: {point(), [module()]}
  def travel(%__MODULE__{edges: edges} = map, from, to) do
    {point, stopped} =
      Enum.reduce(edges, {to, []}, fn {module, options}, {target, stopped} ->
        case module.stop(options, map, from, target) do
          {:clear, point} -> {point, stopped}
          {:stopped, point} -> {point, [module | stopped]}
        end
      end)

    {point, Enum.reverse(stopped)}
  end

  defp square(%__MODULE__{cell_size: size, samples: samples} = map, {x, y} = point) do
    {column, row} = address = address(map, point)

    with %Cell{} = cell <- cell(map, address) do
      step = size / samples
      {across, right} = within((x - column * size) / step, samples)
      {along, up} = within((y - row * size) / step, samples)
      {cell, across, along, right, up}
    end
  end

  defp within(steps, samples) do
    whole = steps |> trunc() |> min(samples - 1) |> max(0)
    {whole, steps - whole}
  end

  defp corners(cell, samples, across, along) do
    {Cell.height(cell, samples, across, along), Cell.height(cell, samples, across + 1, along),
     Cell.height(cell, samples, across, along + 1),
     Cell.height(cell, samples, across + 1, along + 1)}
  end

  defp on_triangle({low, right_low, up_low, _far}, right, up) when right + up <= 1.0,
    do: low + (right_low - low) * right + (up_low - low) * up

  defp on_triangle({_low, right_low, up_low, far}, right, up),
    do: far + (up_low - far) * (1.0 - right) + (right_low - far) * (1.0 - up)

  defp rise({low, right_low, up_low, _far}, right, up, step) when right + up <= 1.0,
    do: {(right_low - low) / step, (up_low - low) / step}

  defp rise({_low, right_low, up_low, far}, _right, _up, step),
    do: {(far - up_low) / step, (far - right_low) / step}
end
