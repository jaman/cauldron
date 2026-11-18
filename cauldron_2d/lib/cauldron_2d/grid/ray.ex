defmodule Cauldron2D.Grid.Ray do
  @moduledoc """
  Lines across a grid of tiles: whether one thing can see another, where a shot that hits
  at once lands, what a laser crosses. A line visits every tile it passes through in
  order, corners included, so it slips through no gap between two walls that only touch
  at a corner.

      case Cauldron2D.Grid.Ray.cast({archer.x, archer.y}, {hero.x, hero.y}, &solid?/1) do
        :clear -> fire(...)
        {:hit, _tile, _point} -> wait(...)
      end

  Points are in tiles, `y` growing downward; tile `{tx, ty}` covers `tx..tx + 1` and
  `ty..ty + 1`. A line starting inside a solid tile hits it at once.
  """

  @type point :: {number(), number()}
  @type tile :: {integer(), integer()}

  @doc """
  The line from `from` to `to`: `:clear` when no tile on it is `solid?`, else
  `{:hit, tile, point}`, the first solid tile and where the line enters it.
  """
  @spec cast(point(), point(), (tile() -> boolean())) :: :clear | {:hit, tile(), point()}
  def cast(from, to, solid?) do
    Enum.find_value(tiles(from, to), :clear, fn {tile, point} ->
      if solid?.(tile), do: {:hit, tile, point}
    end)
  end

  @doc "Whether no tile between `from` and `to` is `solid?`."
  @spec clear?(point(), point(), (tile() -> boolean())) :: boolean()
  def clear?(from, to, solid?), do: cast(from, to, solid?) == :clear

  @doc "Every tile the line from `from` to `to` passes through, in order, each with the point where the line enters it."
  @spec tiles(point(), point()) :: [{tile(), point()}]
  def tiles({x0, y0} = from, {x1, y1}) do
    {dx, dy} = {x1 - x0, y1 - y0}
    start = {floor(x0), floor(y0)}

    line = %{
      from: from,
      delta: {dx, dy},
      last: {floor(x1), floor(y1)},
      x: axis(x0, dx),
      y: axis(y0, dy)
    }

    line |> walk(start, [{start, from}]) |> Enum.reverse()
  end

  defp axis(_start, delta) when delta == 0, do: {0, :infinity, :infinity}
  defp axis(start, delta) when delta > 0, do: {1, (floor(start) + 1 - start) / delta, 1 / delta}
  defp axis(start, delta), do: {-1, (start - floor(start)) / -delta, 1 / -delta}

  defp walk(%{last: tile}, tile, visited), do: visited

  defp walk(line, tile, visited) do
    case crossing(line) do
      nil -> visited
      {axis, t} -> cross(line, tile, axis, t, visited)
    end
  end

  defp crossing(%{x: {_sx, nx, _ex}, y: {_sy, ny, _ey}}) do
    cond do
      nx == :infinity and ny == :infinity -> nil
      ny == :infinity or (nx != :infinity and nx <= ny) -> if nx <= 1, do: {:x, nx}
      true -> if ny <= 1, do: {:y, ny}
    end
  end

  defp cross(line, {tx, ty}, axis, t, visited) do
    {sign, next, each} = Map.fetch!(line, axis)
    tile = if axis == :x, do: {tx + sign, ty}, else: {tx, ty + sign}
    {{x0, y0}, {dx, dy}} = {line.from, line.delta}

    line
    |> Map.put(axis, {sign, next + each, each})
    |> walk(tile, [{tile, {x0 + dx * t, y0 + dy * t}} | visited])
  end
end
