defmodule Cauldron2D.Grid.Fov do
  @moduledoc """
  Recursive shadowcasting: which tiles an observer can see from where it stands.

      Cauldron2D.Grid.Fov.compute(&transparent?/1, {12, 9}, 8)
      #=> MapSet.new([{12, 9}, {12, 8}, ...])

  The map is walked as eight octants, each a wedge scanned row by row away from the
  observer; an opaque tile splits the wedge and what is behind it is not visited, so the
  cost follows what is visible rather than the area of the circle.

  Two rules a caller can rely on:

    * Walls bounding a lit area are lit: an opaque tile is added to the set before it
      stops the scan.
    * Visibility is mutual: if `b` is in the set computed from `a`, `a` is in the set
      computed from `b` at the same radius.

  `transparent?` is a function from a tile to whether sight passes through it; a tile
  outside the map should answer `false`. `origin` itself is always in the set.
  """

  @type point :: {integer(), integer()}
  @type transparent :: (point() -> boolean())

  @octants [
    {1, 0, 0, 1},
    {0, 1, 1, 0},
    {0, -1, 1, 0},
    {-1, 0, 0, 1},
    {-1, 0, 0, -1},
    {0, -1, -1, 0},
    {0, 1, -1, 0},
    {1, 0, 0, -1}
  ]

  @doc "The set of tiles visible from `origin` within `radius`, measured as Euclidean distance."
  @spec compute(transparent(), point(), pos_integer()) :: MapSet.t(point())
  def compute(transparent?, origin, radius) when is_function(transparent?, 1) do
    Enum.reduce(@octants, MapSet.new([origin]), fn octant, seen ->
      cast(transparent?, origin, radius, octant, 1, 1.0, 0.0, seen)
    end)
  end

  defp cast(_transparent?, _origin, radius, _octant, row, start_slope, end_slope, seen)
       when row > radius or start_slope < end_slope,
       do: seen

  defp cast(transparent?, origin, radius, octant, row, start_slope, end_slope, seen) do
    {seen, start_slope, blocked?} =
      sweep(transparent?, origin, radius, octant, row, start_slope, end_slope, seen)

    if blocked? do
      seen
    else
      cast(transparent?, origin, radius, octant, row + 1, start_slope, end_slope, seen)
    end
  end

  defp sweep(transparent?, origin, radius, octant, row, start_slope, end_slope, seen) do
    row..0//-1
    |> Enum.reduce_while({seen, start_slope, start_slope, false}, fn col, acc ->
      column(transparent?, origin, radius, octant, {row, col}, end_slope, acc)
    end)
    |> then(fn {seen, start, _pending, blocked?} -> {seen, start, blocked?} end)
  end

  defp column(transparent?, origin, radius, octant, {row, col}, end_slope, acc) do
    {_seen, start, _pending, _blocked?} = acc
    left = (col + 0.5) / (row - 0.5)
    right = (col - 0.5) / (row + 0.5)

    cond do
      right > start -> {:cont, acc}
      left < end_slope -> {:halt, acc}
      true -> {:cont, mark(transparent?, origin, radius, octant, {row, col}, {left, right}, acc)}
    end
  end

  defp mark(transparent?, origin, radius, octant, {row, col}, {left, right}, acc) do
    {seen, start, pending, blocked?} = acc
    point = translate(origin, octant, row, col)
    seen = if within?(origin, point, radius), do: MapSet.put(seen, point), else: seen

    case {blocked?, transparent?.(point)} do
      {true, false} ->
        {seen, start, right, true}

      {true, true} ->
        {seen, pending, pending, false}

      {false, false} ->
        {cast(transparent?, origin, radius, octant, row + 1, start, left, seen), start, right,
         true}

      {false, true} ->
        {seen, start, pending, false}
    end
  end

  defp translate({ox, oy}, {xx, xy, yx, yy}, row, col),
    do: {ox + col * xx + row * xy, oy + col * yx + row * yy}

  defp within?({ox, oy}, {x, y}, radius) do
    dx = x - ox
    dy = y - oy
    dx * dx + dy * dy <= radius * radius
  end
end
