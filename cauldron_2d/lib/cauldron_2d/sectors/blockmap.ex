defmodule Cauldron2D.Sectors.Blockmap do
  @moduledoc """
  A sector map's lines, and the bodies moving through it, sorted into square blocks so
  that movement and traces only look at what is near.

      blockmap =
        map
        |> Cauldron2D.Sectors.Blockmap.build(size: 128)
        |> Cauldron2D.Sectors.Blockmap.with_bodies([{:player, {1056.0, -3616.0}, 16.0}, ...])

      Cauldron2D.Sectors.Blockmap.lines_near(blockmap, {x, y}, 16.0)
      Cauldron2D.Sectors.Blockmap.bodies_near(blockmap, {x, y}, 16.0)

  Lines are filed once, when the blockmap is built; bodies move, so `with_bodies/2` files
  a fresh set and replaces the last, and `put_body/2` and `remove_body/2` file or unfile
  one as it moves. A body is `{id, {x, y}, radius}`.
  """

  @enforce_keys [:origin, :size, :columns, :rows, :cells]
  defstruct [:origin, :size, :columns, :rows, :cells, bodies: %{}, filed: %{}, widest: 0.0]

  @type body :: {term(), {number(), number()}, number()}
  @type t :: %__MODULE__{
          origin: {float(), float()},
          size: number(),
          columns: pos_integer(),
          rows: pos_integer(),
          cells: tuple(),
          bodies: %{integer() => [body()]},
          filed: %{term() => integer()},
          widest: float()
        }

  @doc "File the lines of `map` (a `Cauldron2D.Sectors.Map`). Option `:size`, the block's side, default `128`."
  @spec build(Cauldron2D.Sectors.Map.t(), keyword()) :: t()
  def build(map, opts \\ []) do
    size = Keyword.get(opts, :size, 128)
    points = Tuple.to_list(map.vertices)
    {xs, ys} = Enum.unzip(points)
    {x0, y0} = {Enum.min(xs) - 8.0, Enum.min(ys) - 8.0}
    columns = max(1, trunc(Float.ceil((Enum.max(xs) + 8.0 - x0) / size)))
    rows = max(1, trunc(Float.ceil((Enum.max(ys) + 8.0 - y0) / size)))
    empty = %__MODULE__{origin: {x0, y0}, size: size, columns: columns, rows: rows, cells: {}}

    cells =
      0..(tuple_size(map.lines) - 1)//1
      |> Enum.reduce(%{}, fn index, acc ->
        line = elem(map.lines, index)
        ends = {elem(map.vertices, line.from), elem(map.vertices, line.to)}

        Enum.reduce(cells_of_segment(empty, ends), acc, fn cell, cells ->
          Map.update(cells, cell, [index], &[index | &1])
        end)
      end)

    %{
      empty
      | cells:
          List.to_tuple(
            for cell <- 0..(columns * rows - 1), do: cells |> Map.get(cell, []) |> Enum.reverse()
          )
    }
  end

  @doc "The blockmap with `bodies` filed, replacing the ones filed before."
  @spec with_bodies(t(), [body()]) :: t()
  def with_bodies(%__MODULE__{} = blockmap, bodies),
    do: Enum.reduce(bodies, %{blockmap | bodies: %{}, filed: %{}, widest: 0.0}, &put_body(&2, &1))

  @doc "File `body`, moving it if a body with its id is filed already."
  @spec put_body(t(), body()) :: t()
  def put_body(%__MODULE__{} = blockmap, {id, point, radius} = body) do
    blockmap = remove_body(blockmap, id)
    cell = cell_of(blockmap, point)

    %{
      blockmap
      | bodies: Map.update(blockmap.bodies, cell, [body], &[body | &1]),
        filed: Map.put(blockmap.filed, id, cell),
        widest: max(blockmap.widest, radius * 1.0)
    }
  end

  @doc "Unfile the body with `id`, if one is filed."
  @spec remove_body(t(), term()) :: t()
  def remove_body(%__MODULE__{} = blockmap, id) do
    case Map.pop(blockmap.filed, id) do
      {nil, _filed} ->
        blockmap

      {cell, filed} ->
        rest = blockmap.bodies |> Map.get(cell, []) |> Enum.reject(&(elem(&1, 0) == id))
        %{blockmap | bodies: Map.put(blockmap.bodies, cell, rest), filed: filed}
    end
  end

  @doc "The indexes of lines filed in the blocks a box of `radius` round `point` touches."
  @spec lines_near(t(), {number(), number()}, number()) :: [non_neg_integer()]
  def lines_near(%__MODULE__{} = blockmap, {x, y}, radius) do
    blockmap
    |> cells_of_box({x - radius, y - radius, x + radius, y + radius})
    |> Enum.flat_map(&elem(blockmap.cells, &1))
    |> Enum.uniq()
  end

  @doc "The bodies whose box overlaps a box of `radius` round `point`."
  @spec bodies_near(t(), {number(), number()}, number()) :: [body()]
  def bodies_near(%__MODULE__{} = blockmap, {x, y}, radius) do
    reach = radius + blockmap.widest

    blockmap
    |> cells_of_box({x - reach, y - reach, x + reach, y + reach})
    |> Enum.flat_map(&Map.get(blockmap.bodies, &1, []))
    |> Enum.filter(fn {_id, {bx, by}, body_radius} ->
      abs(bx - x) < radius + body_radius and abs(by - y) < radius + body_radius
    end)
  end

  @doc "The blocks a segment passes through, in order from `from` to `to`, as block numbers."
  @spec cells_of_segment(t(), {{number(), number()}, {number(), number()}}) :: [non_neg_integer()]
  def cells_of_segment(%__MODULE__{} = blockmap, {{x1, y1}, {x2, y2}}) do
    {ox, oy} = blockmap.origin
    size = blockmap.size
    {gx1, gy1} = {(x1 - ox) / size, (y1 - oy) / size}
    {gx2, gy2} = {(x2 - ox) / size, (y2 - oy) / size}
    {cx, cy} = {floor(gx1), floor(gy1)}
    {ex, ey} = {floor(gx2), floor(gy2)}
    {dx, dy} = {gx2 - gx1, gy2 - gy1}
    step_x = if dx > 0, do: 1, else: -1
    step_y = if dy > 0, do: 1, else: -1
    t_dx = if dx == 0, do: :infinity, else: abs(1 / dx)
    t_dy = if dy == 0, do: :infinity, else: abs(1 / dy)
    t_x = boundary(gx1, cx, dx, t_dx)
    t_y = boundary(gy1, cy, dy, t_dy)
    limit = abs(ex - cx) + abs(ey - cy) + 2

    {cx, cy}
    |> walk_cells({t_x, t_y}, limit, {step_x, step_y, t_dx, t_dy}, {ex, ey}, [])
    |> Enum.filter(fn {x, y} ->
      x >= 0 and y >= 0 and x < blockmap.columns and y < blockmap.rows
    end)
    |> Enum.map(fn {x, y} -> y * blockmap.columns + x end)
  end

  defp boundary(_g, _cell, _d, :infinity), do: :infinity
  defp boundary(g, cell, d, t_d) when d > 0, do: (cell + 1 - g) * t_d
  defp boundary(g, cell, _d, t_d), do: (g - cell) * t_d

  defp walk_cells(at, _times, left, _steps, finish, acc) when at == finish or left <= 0,
    do: Enum.reverse([at | acc])

  defp walk_cells({x, y} = at, {tx, ty}, left, {sx, sy, t_dx, t_dy} = steps, finish, acc) do
    if smaller?(tx, ty),
      do: walk_cells({x + sx, y}, {add(tx, t_dx), ty}, left - 1, steps, finish, [at | acc]),
      else: walk_cells({x, y + sy}, {tx, add(ty, t_dy)}, left - 1, steps, finish, [at | acc])
  end

  defp smaller?(:infinity, _b), do: false
  defp smaller?(_a, :infinity), do: true
  defp smaller?(a, b), do: a < b

  defp add(:infinity, _b), do: :infinity
  defp add(a, b), do: a + b

  defp cells_of_box(blockmap, {x1, y1, x2, y2}) do
    {ox, oy} = blockmap.origin
    size = blockmap.size
    left = max(floor((x1 - ox) / size), 0)
    right = min(floor((x2 - ox) / size), blockmap.columns - 1)
    bottom = max(floor((y1 - oy) / size), 0)
    top = min(floor((y2 - oy) / size), blockmap.rows - 1)
    for y <- bottom..top//1, x <- left..right//1, do: y * blockmap.columns + x
  end

  defp cell_of(blockmap, {x, y}) do
    {ox, oy} = blockmap.origin
    column = floor((x - ox) / blockmap.size)
    row = floor((y - oy) / blockmap.size)
    row * blockmap.columns + column
  end
end
