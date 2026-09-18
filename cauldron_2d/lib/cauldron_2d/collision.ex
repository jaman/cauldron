defmodule Cauldron2D.Collision do
  @moduledoc """
  Bodies against a tile grid, and against each other.

  The grid is a function from a tile coordinate to what is there:

      :open                          nothing
      :solid                         the whole tile
      {:diagonal, :nw | :ne | :sw | :se}   the half toward that corner

  `sweep/5` moves a body of some radius from one point to another in steps no longer than
  a quarter tile, so nothing passes through a wall however fast it travels, and reports the
  last clear point, the surface normal and the tile it would have entered. `bounce/3`
  reflects a velocity off that normal.

      case Cauldron2D.Collision.sweep(grid, from, to, radius) do
        {:clear, at} -> at
        {:blocked, at, normal, cell} -> ...
      end

  `Cauldron2D.Collision.Buckets` finds bodies near each other without comparing every pair.
  """

  @type point :: {float(), float()}
  @type cell :: {integer(), integer()}
  @type corner :: :nw | :ne | :sw | :se
  @type solid :: :open | :solid | {:diagonal, corner()}
  @type grid :: (cell() -> solid())
  @type normal :: {float(), float()}

  @substep 0.25
  @ring 8

  @doc "Whether `point` lies in solid material."
  @spec inside?(grid(), point()) :: boolean()
  def inside?(grid, {x, y} = point) do
    cell = cell_of(point)
    filled?(grid.(cell), local(cell, {x, y}))
  end

  defp filled?(:open, _local), do: false
  defp filled?(:solid, _local), do: true
  defp filled?({:diagonal, :se}, {lx, ly}), do: lx + ly >= 1.0
  defp filled?({:diagonal, :nw}, {lx, ly}), do: lx + ly <= 1.0
  defp filled?({:diagonal, :ne}, {lx, ly}), do: lx >= ly
  defp filled?({:diagonal, :sw}, {lx, ly}), do: lx <= ly

  @doc """
  Move a body of `radius` from `from` to `to`.

  Returns `{:clear, to}` when nothing is in the way, or
  `{:blocked, at, normal, cell}` with the last clear position, the unit normal of the
  surface struck, and the tile struck. A body already inside a wall is blocked at `from`
  with a normal opposing its motion.
  """
  @spec sweep(grid(), point(), point(), number()) ::
          {:clear, point()} | {:blocked, point(), normal(), cell()}
  def sweep(grid, {fx, fy} = from, {tx, ty} = to, radius) do
    case struck(grid, from, radius) do
      {:hit, cell, _sample} ->
        {:blocked, from, opposing({tx - fx, ty - fy}), cell}

      :none ->
        distance = :math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy))
        steps = max(1, ceil(distance / @substep))
        march(grid, from, to, radius, 1, steps, from)
    end
  end

  defp march(_grid, _from, to, _radius, step, steps, _previous) when step > steps do
    {:clear, to}
  end

  defp march(grid, {fx, fy} = from, {tx, ty} = to, radius, step, steps, previous) do
    point = {fx + (tx - fx) * step / steps, fy + (ty - fy) * step / steps}

    case struck(grid, point, radius) do
      {:hit, cell, sample} ->
        {normal, struck} = surface_normal(grid, cell, shifted(previous, point, sample), sample)
        {:blocked, previous, normal, struck}

      :none ->
        march(grid, from, to, radius, step + 1, steps, point)
    end
  end

  defp shifted({px, py}, {x, y}, {sx, sy}), do: {sx - (x - px), sy - (y - py)}

  defp struck(grid, point, radius) do
    point
    |> samples(radius)
    |> Enum.find_value(:none, fn sample ->
      if inside?(grid, sample), do: {:hit, cell_of(sample), sample}
    end)
  end

  defp samples(point, radius) when radius <= 0, do: [point]

  defp samples({x, y} = point, radius) do
    ring =
      for k <- 0..(@ring - 1) do
        theta = 2 * :math.pi() * k / @ring
        {x + radius * :math.cos(theta), y + radius * :math.sin(theta)}
      end

    [point | ring]
  end

  defp surface_normal(grid, cell, from_point, to_point) do
    from_cell = cell_of(from_point)

    case {grid.(cell), from_cell == cell} do
      {{:diagonal, corner}, true} ->
        {diagonal_normal(corner), cell}

      {{:diagonal, corner}, false} ->
        {face, struck} = entered_face(grid, cell, from_cell, from_point, to_point)

        if struck == cell and face not in solid_faces(corner),
          do: {diagonal_normal(corner), cell},
          else: {face_normal(face), struck}

      {_solid, _} ->
        {face, struck} = entered_face(grid, cell, from_cell, from_point, to_point)
        {face_normal(face), struck}
    end
  end

  defp entered_face(grid, {cx, cy} = cell, {fx, fy}, {px, py}, {x, y}) do
    dx = cx - fx
    dy = cy - fy

    cond do
      dx != 0 and dy == 0 -> {horizontal_entry(dx), cell}
      dy != 0 and dx == 0 -> {vertical_entry(dy), cell}
      true -> across_corner(grid, cell, {fx, fy}, {dx, dy}, {px, py}, {x, y})
    end
  end

  defp across_corner(grid, {cx, cy} = cell, {fx, fy}, {dx, dy}, {px, py}, {x, y}) do
    face_x = if dx > 0, do: cx, else: cx + 1
    face_y = if dy > 0, do: cy, else: cy + 1
    tx = crossing(px, x, face_x)
    ty = crossing(py, y, face_y)

    {first, between} =
      if tx <= ty,
        do: {horizontal_entry(dx), {cx, fy}},
        else: {vertical_entry(dy), {fx, cy}}

    if filled?(grid.(between), local(between, midpoint({px, py}, {x, y}))) do
      {first, between}
    else
      {if(tx <= ty, do: vertical_entry(dy), else: horizontal_entry(dx)), cell}
    end
  end

  defp midpoint({px, py}, {x, y}), do: {(px + x) / 2, (py + y) / 2}

  defp horizontal_entry(dx) when dx > 0, do: :west
  defp horizontal_entry(_dx), do: :east
  defp vertical_entry(dy) when dy > 0, do: :north
  defp vertical_entry(_dy), do: :south

  defp crossing(from, to, _face) when to == from, do: 1.0
  defp crossing(from, to, face), do: (face - from) / (to - from)

  defp solid_faces(:se), do: [:east, :south]
  defp solid_faces(:nw), do: [:west, :north]
  defp solid_faces(:ne), do: [:east, :north]
  defp solid_faces(:sw), do: [:west, :south]

  defp face_normal(:west), do: {-1.0, 0.0}
  defp face_normal(:east), do: {1.0, 0.0}
  defp face_normal(:north), do: {0.0, -1.0}
  defp face_normal(:south), do: {0.0, 1.0}

  @half_root :math.sqrt(0.5)
  defp diagonal_normal(:se), do: {-@half_root, -@half_root}
  defp diagonal_normal(:nw), do: {@half_root, @half_root}
  defp diagonal_normal(:ne), do: {-@half_root, @half_root}
  defp diagonal_normal(:sw), do: {@half_root, -@half_root}

  defp opposing({dx, dy}) do
    case :math.sqrt(dx * dx + dy * dy) do
      length when length > 0 -> {-dx / length, -dy / length}
      _still -> {0.0, -1.0}
    end
  end

  @doc """
  Reflect `velocity` off a surface with unit `normal`.

  The component along the normal is reversed and scaled by `restitution`; the component
  along the surface is kept. A velocity already moving away from the surface is returned
  unchanged.
  """
  @spec bounce(point(), normal(), number()) :: point()
  def bounce({vx, vy} = velocity, {nx, ny}, restitution) do
    along = vx * nx + vy * ny

    if along >= 0 do
      velocity
    else
      {vx - (1 + restitution) * along * nx, vy - (1 + restitution) * along * ny}
    end
  end

  @doc "Whether two circles overlap."
  @spec circles_overlap?(point(), number(), point(), number()) :: boolean()
  def circles_overlap?({x1, y1}, r1, {x2, y2}, r2) do
    dx = x2 - x1
    dy = y2 - y1
    reach = r1 + r2
    dx * dx + dy * dy < reach * reach
  end

  @doc "The square of the distance between two points."
  @spec distance_sq(point(), point()) :: float()
  def distance_sq({x1, y1}, {x2, y2}), do: (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) * 1.0

  @doc "The tile a point is in."
  @spec cell_of(point()) :: cell()
  def cell_of({x, y}), do: {floor(x), floor(y)}

  defp local({cx, cy}, {x, y}), do: {x - cx, y - cy}
end
