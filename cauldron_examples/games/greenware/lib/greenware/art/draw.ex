defmodule Greenware.Art.Draw do
  @moduledoc "`Cauldron2D.Shapes`, drawing in 640 by 360 design units onto the 2x frame."

  alias Cauldron2D.Shapes

  @k 2

  def fill_rect(raster, {x1, y1}, {x2, y2}, colour),
    do: Shapes.fill_rect(raster, {x1 * @k, y1 * @k}, {x2 * @k, y2 * @k}, colour)

  def rect(raster, {x1, y1}, {x2, y2}, colour),
    do: Shapes.rect(raster, {x1 * @k, y1 * @k}, {x2 * @k, y2 * @k}, colour)

  def fill_circle(raster, {x, y}, radius, colour),
    do: Shapes.fill_circle(raster, {x * @k, y * @k}, radius * @k, colour)

  def circle(raster, {x, y}, radius, colour),
    do: Shapes.circle(raster, {x * @k, y * @k}, radius * @k, colour)

  def line(raster, {x1, y1}, {x2, y2}, colour),
    do: Shapes.line(raster, {x1 * @k, y1 * @k}, {x2 * @k, y2 * @k}, colour)

  def polyline(raster, points, colour),
    do: Shapes.polyline(raster, Enum.map(points, fn {x, y} -> {x * @k, y * @k} end), colour)

  def fill_polygon(raster, points, colour),
    do: Shapes.fill_polygon(raster, Enum.map(points, fn {x, y} -> {x * @k, y * @k} end), colour)
end
