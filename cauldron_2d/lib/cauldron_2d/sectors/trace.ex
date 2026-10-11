defmodule Cauldron2D.Sectors.Trace do
  @moduledoc """
  What a straight line across a sector map crosses, nearest first: the map's lines and
  the bodies filed in a `Cauldron2D.Sectors.Blockmap`.

      Cauldron2D.Sectors.Trace.run(map, blockmap, {x, y}, {x + 2048.0, y})
      #=> [%{fraction: 0.12, line: 4}, %{fraction: 0.31, body: :imp_7, at: {..}, radius: 20.0}, ...]

  `fraction` is how far along from `from` to `to` the crossing is, `0.0..1.0`. A line is
  crossed where the trace meets it; a body where the trace first enters its circle, or at
  `0.0` where `from` is already inside it. Instant-hit weapons, line of sight, reaching for
  a switch and sliding along a wall are all built on this.

  ## Options

    * `:lines` — include lines. Default `true`
    * `:bodies` — include bodies. Default `true`
    * `:except` — a body id to leave out, such as the one tracing. Default `nil`
  """

  alias Cauldron2D.Sectors.Blockmap

  @type intercept ::
          %{fraction: float(), line: non_neg_integer()}
          | %{fraction: float(), body: term(), at: {float(), float()}, radius: float()}

  @doc "The intercepts from `from` to `to`, nearest first. See the moduledoc."
  @spec run(
          Cauldron2D.Sectors.Map.t(),
          Blockmap.t(),
          {number(), number()},
          {number(), number()},
          keyword()
        ) ::
          [intercept()]
  def run(map, %Blockmap{} = blockmap, from, to, opts \\ []) do
    cells = Blockmap.cells_of_segment(blockmap, {from, to})

    lines =
      if Keyword.get(opts, :lines, true),
        do: line_intercepts(map, blockmap, cells, from, to),
        else: []

    bodies =
      if Keyword.get(opts, :bodies, true),
        do: body_intercepts(blockmap, cells, from, to, Keyword.get(opts, :except)),
        else: []

    Enum.sort_by(lines ++ bodies, & &1.fraction)
  end

  defp line_intercepts(map, blockmap, cells, from, to) do
    cells
    |> Enum.flat_map(&elem(blockmap.cells, &1))
    |> Enum.uniq()
    |> Enum.flat_map(fn index ->
      line = elem(map.lines, index)

      case crossing(from, to, elem(map.vertices, line.from), elem(map.vertices, line.to)) do
        nil -> []
        fraction -> [%{fraction: fraction, line: index}]
      end
    end)
  end

  @doc "Where segment `a1`–`a2` meets segment `b1`–`b2`, as a fraction along the first, or `nil`."
  @spec crossing(
          {number(), number()},
          {number(), number()},
          {number(), number()},
          {number(), number()}
        ) ::
          float() | nil
  def crossing({ax, ay}, {bx, by}, {cx, cy}, {dx, dy}) do
    {rx, ry} = {bx - ax, by - ay}
    {sx, sy} = {dx - cx, dy - cy}
    denominator = rx * sy - ry * sx

    if abs(denominator) < 1.0e-12 do
      nil
    else
      {qx, qy} = {cx - ax, cy - ay}
      t = (qx * sy - qy * sx) / denominator
      u = (qx * ry - qy * rx) / denominator
      if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0, do: t, else: nil
    end
  end

  defp body_intercepts(blockmap, cells, from, to, except) do
    reach = blockmap.size

    cells
    |> Enum.flat_map(fn cell ->
      {x, y} = centre(blockmap, cell)
      Blockmap.bodies_near(blockmap, {x, y}, reach / 2)
    end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.reject(fn {id, _point, _radius} -> id == except end)
    |> Enum.flat_map(fn {id, point, radius} ->
      case entry(from, to, point, radius) do
        nil -> []
        fraction -> [%{fraction: fraction, body: id, at: point, radius: radius * 1.0}]
      end
    end)
  end

  defp centre(blockmap, cell) do
    {ox, oy} = blockmap.origin
    column = rem(cell, blockmap.columns)
    row = div(cell, blockmap.columns)
    {ox + (column + 0.5) * blockmap.size, oy + (row + 0.5) * blockmap.size}
  end

  defp entry({ax, ay}, {bx, by}, {cx, cy}, radius) do
    {dx, dy} = {bx - ax, by - ay}
    {fx, fy} = {ax - cx, ay - cy}
    a = dx * dx + dy * dy
    b = 2 * (fx * dx + fy * dy)
    c = fx * fx + fy * fy - radius * radius

    cond do
      c <= 0 -> 0.0
      a == 0 -> nil
      true -> first_root(a, b, c)
    end
  end

  defp first_root(a, b, c) do
    discriminant = b * b - 4 * a * c

    if discriminant < 0 do
      nil
    else
      t = (-b - :math.sqrt(discriminant)) / (2 * a)
      if t >= 0.0 and t <= 1.0, do: t, else: nil
    end
  end
end
