defmodule Cauldron3D.WalkGrid do
  @moduledoc """
  Where something walking on a flat floor can go, as a grid of square cells seen from
  above. A cell is blocked when a triangle crosses it anywhere between `:low` and `:high`
  above the floor, so walls, pillars and furniture block and the floor, ceilings and
  anything overhead do not. Outside the grid's bounds is blocked.

      grid = Cauldron3D.WalkGrid.build({{-20.0, -10.0}, {20.0, 10.0}}, [{positions, indices, transform}])
      Cauldron3D.WalkGrid.slide(grid, {0.0, 0.0}, {0.1, 0.0}, 0.3)

  A source is `{positions, indices, transform}`: positions as little-endian 32-bit floats,
  three a vertex; indices as little-endian unsigned 32-bit integers, three a triangle;
  and the transform placing them (`Cauldron3D.Skeleton.transform/2` form). Points are
  `{x, z}`.

  ## Options

    * `:cell` — the side of a cell in metres. Default `0.1`
    * `:floor` — the floor's height. Default `0.0`
    * `:low`, `:high` — the band above the floor that blocks. Default `0.3` and `1.8`
    * `:discs` — `{{x, z}, radius}` areas blocked as well
  """

  alias Cauldron3D.Skeleton

  @type point :: {float(), float()}
  @type source :: {binary(), binary(), Skeleton.transform()}
  @type t :: %__MODULE__{
          origin: point(),
          cell: float(),
          columns: pos_integer(),
          rows: pos_integer(),
          blocked: binary()
        }

  @enforce_keys [:origin, :cell, :columns, :rows, :blocked]
  defstruct [:origin, :cell, :columns, :rows, :blocked]

  @doc "The grid over `bounds` (`{{min_x, min_z}, {max_x, max_z}}`) with `sources` blocking it."
  @spec build({point(), point()}, [source()], keyword()) :: t()
  def build({{min_x, min_z}, {max_x, max_z}}, sources, opts \\ []) do
    cell = Keyword.get(opts, :cell, 0.1)
    floor = Keyword.get(opts, :floor, 0.0)
    band = {floor + Keyword.get(opts, :low, 0.3), floor + Keyword.get(opts, :high, 1.8)}
    columns = max(1, ceil((max_x - min_x) / cell))
    rows = max(1, ceil((max_z - min_z) / cell))
    marks = :atomics.new(columns * rows, signed: false)

    grid = %__MODULE__{
      origin: {min_x, min_z},
      cell: cell,
      columns: columns,
      rows: rows,
      blocked: <<>>
    }

    Enum.each(sources, &mark_source(grid, marks, &1, band))
    Enum.each(Keyword.get(opts, :discs, []), &mark_disc(grid, marks, &1))

    %{
      grid
      | blocked: for(index <- 1..(columns * rows), into: <<>>, do: <<:atomics.get(marks, index)>>)
    }
  end

  @doc "Whether the cell under `point` is blocked."
  @spec blocked?(t(), point()) :: boolean()
  def blocked?(%__MODULE__{} = grid, point) do
    case cell_of(grid, point) do
      nil -> true
      {column, row} -> :binary.at(grid.blocked, row * grid.columns + column) != 0
    end
  end

  @doc "Whether a body of `radius` fits at `point`."
  @spec free?(t(), point(), float()) :: boolean()
  def free?(%__MODULE__{cell: cell} = grid, {x, z}, radius) do
    steps = ceil(radius / cell)

    Enum.all?(for(dx <- -steps..steps, dz <- -steps..steps, do: {dx * cell, dz * cell}), fn
      {ox, oz} when ox * ox + oz * oz > (radius + cell / 2) * (radius + cell / 2) -> true
      {ox, oz} -> not blocked?(grid, {x + ox, z + oz})
    end)
  end

  @doc """
  Where a body of `radius` moving from `from` towards `to` ends up: at `to` when it fits,
  else as far as it fits along X alone or Z alone, else at `from`.
  """
  @spec slide(t(), point(), point(), float()) :: point()
  def slide(%__MODULE__{} = grid, {fx, fz} = from, {tx, tz} = to, radius) do
    Enum.find([to, {tx, fz}, {fx, tz}], from, &free?(grid, &1, radius))
  end

  @doc """
  The farthest point from `from` towards `to` that a body of `radius` reaches without
  meeting a blocked cell; `from` itself when it is already in one.
  """
  @spec reach(t(), point(), point(), float()) :: point()
  def reach(%__MODULE__{cell: cell} = grid, {fx, fz} = from, {tx, tz}, radius) do
    length = :math.sqrt((tx - fx) * (tx - fx) + (tz - fz) * (tz - fz))
    steps = max(1, ceil(length / (cell / 2)))

    1..steps
    |> Enum.reduce_while(from, fn step, reached ->
      t = step / steps
      point = {fx + (tx - fx) * t, fz + (tz - fz) * t}
      if free?(grid, point, radius), do: {:cont, point}, else: {:halt, reached}
    end)
  end

  defp cell_of(%__MODULE__{origin: {ox, oz}, cell: cell, columns: columns, rows: rows}, {x, z}) do
    column = floor((x - ox) / cell)
    row = floor((z - oz) / cell)
    if column >= 0 and column < columns and row >= 0 and row < rows, do: {column, row}
  end

  defp mark(grid, marks, point) do
    case cell_of(grid, point) do
      nil -> :ok
      {column, row} -> :atomics.put(marks, row * grid.columns + column + 1, 1)
    end
  end

  defp mark_source(grid, marks, {positions, indices, transform}, band) do
    for <<a::little-32, b::little-32, c::little-32 <- indices>> do
      mark_triangle(
        grid,
        marks,
        vertex(positions, a, transform),
        vertex(positions, b, transform),
        vertex(positions, c, transform),
        band
      )
    end

    :ok
  end

  defp vertex(positions, index, transform) do
    <<x::little-float-32, y::little-float-32, z::little-float-32>> =
      binary_part(positions, index * 12, 12)

    Skeleton.apply(transform, {x, y, z})
  end

  defp mark_triangle(grid, marks, {ax, ay, az}, {bx, by, bz}, {cx, cy, cz}, {low, high}) do
    if max(ay, max(by, cy)) >= low and min(ay, min(by, cy)) <= high do
      span = max(edge(ax, az, bx, bz), max(edge(bx, bz, cx, cz), edge(cx, cz, ax, az)))
      steps = max(1, ceil(span / (grid.cell / 2)))

      for i <- 0..steps, j <- 0..(steps - i) do
        {u, v} = {i / steps, j / steps}

        mark(
          grid,
          marks,
          {ax + (bx - ax) * u + (cx - ax) * v, az + (bz - az) * u + (cz - az) * v}
        )
      end
    end

    :ok
  end

  defp edge(ax, az, bx, bz), do: :math.sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az))

  defp mark_disc(%__MODULE__{cell: cell} = grid, marks, {{x, z}, radius}) do
    steps = ceil(radius / cell)

    for dx <- -steps..steps,
        dz <- -steps..steps,
        (dx * dx + dz * dz) * cell * cell <= radius * radius do
      mark(grid, marks, {x + dx * cell, z + dz * cell})
    end

    :ok
  end
end
