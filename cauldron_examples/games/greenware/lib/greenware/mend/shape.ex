defmodule Greenware.Mend.Shape do
  @moduledoc "Cell primitives for the clay objects, on a 96 by 72 workbench."

  @width 96
  @height 72

  def width, do: @width
  def height, do: @height

  def point(x, y) when x >= 0 and y >= 0 and x < @width and y < @height, do: MapSet.new([{x, y}])
  def point(_x, _y), do: MapSet.new()

  def rect(x, y, width, height) do
    for cx <- x..(x + width - 1)//1,
        cy <- y..(y + height - 1)//1,
        cx >= 0 and cy >= 0 and cx < @width and cy < @height,
        into: MapSet.new(),
        do: {cx, cy}
  end

  def ellipse(cx, cy, rx, ry) do
    for x <- 0..(@width - 1),
        y <- 0..(@height - 1),
        dx = (x - cx) / rx,
        dy = (y - cy) / ry,
        dx * dx + dy * dy <= 1.0,
        into: MapSet.new(),
        do: {x, y}
  end

  def ring(cx, cy, rx, ry, thickness) do
    outer = ellipse(cx, cy, rx, ry)
    inner = ellipse(cx, cy, max(1, rx - thickness), max(1, ry - thickness))
    MapSet.difference(outer, inner)
  end

  def line({x1, y1}, {x2, y2}, thickness \\ 1) do
    steps = max(abs(x2 - x1), abs(y2 - y1)) * 2 + 1

    Enum.reduce(0..steps, MapSet.new(), fn step, acc ->
      t = step / steps
      x = round(x1 + (x2 - x1) * t)
      y = round(y1 + (y2 - y1) * t)
      MapSet.union(acc, disc(x, y, thickness))
    end)
  end

  def disc(cx, cy, radius) do
    for x <- (cx - radius)..(cx + radius),
        y <- (cy - radius)..(cy + radius),
        x >= 0 and y >= 0 and x < @width and y < @height,
        (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius,
        into: MapSet.new(),
        do: {x, y}
  end

  def polygon(points) do
    xs = Enum.map(points, &elem(&1, 0))
    ys = Enum.map(points, &elem(&1, 1))
    left = max(0, floor(Enum.min(xs)))
    right = min(@width - 1, ceil(Enum.max(xs)))
    top = max(0, floor(Enum.min(ys)))
    bottom = min(@height - 1, ceil(Enum.max(ys)))

    for x <- left..right,
        y <- top..bottom,
        inside?(points, x + 0.5, y + 0.5),
        into: MapSet.new(),
        do: {x, y}
  end

  defp inside?(points, x, y) do
    edges =
      points
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        {point, Enum.at(points, rem(index + 1, length(points)))}
      end)

    Enum.reduce(edges, false, fn {{x1, y1}, {x2, y2}}, inside ->
      if y1 > y != y2 > y and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1,
        do: not inside,
        else: inside
    end)
  end

  def grow(cells, by) do
    Enum.reduce(cells, cells, fn {x, y}, acc ->
      MapSet.union(acc, disc(x, y, by))
    end)
  end

  def intersect(a, b), do: MapSet.intersection(a, b)
  def subtract(a, b), do: MapSet.difference(a, b)
  def union(a, b), do: MapSet.union(a, b)

  def bounds(cells) do
    xs = Enum.map(cells, &elem(&1, 0))
    ys = Enum.map(cells, &elem(&1, 1))
    {Enum.min(xs), Enum.min(ys), Enum.max(xs) - Enum.min(xs) + 1, Enum.max(ys) - Enum.min(ys) + 1}
  end

  def take(cells, count) do
    cells |> Enum.sort() |> Enum.take(count) |> MapSet.new()
  end
end
