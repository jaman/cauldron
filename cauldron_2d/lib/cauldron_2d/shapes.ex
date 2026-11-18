defmodule Cauldron2D.Shapes do
  @moduledoc """
  Lines, rectangles, circles and polygons drawn onto a `Cauldron2D.Raster`, for art made
  in code.

  Every function takes a raster as its first argument and returns a new one, so calls
  compose in a pipeline. Coordinates are integer pixels, `{0, 0}` at the top left, and may
  fall outside the raster: the parts that land inside are drawn and the rest is clipped.
  Colours are `{r, g, b, a}` byte tuples written opaquely, with no blending against what
  is already there.

  Outlines are written as one batch of pixels and filled shapes as one batch of
  horizontal spans, so a call costs one raster update however many pixels it covers.

      Cauldron2D.Raster.new(40, 20)
      |> Cauldron2D.Shapes.rect({0, 0}, {39, 19}, {80, 80, 80, 255})
      |> Cauldron2D.Shapes.fill_circle({20, 10}, 6, {255, 0, 0, 255})
  """

  @type column() :: FrenchCurve.Draw.column()
  @type coord() :: FrenchCurve.Draw.coord()

  @doc """
  Draws a one-pixel-wide circle outline of `radius` pixels around the centre `{cx, cy}`.

  `radius` must be a non-negative integer. The interior is untouched.
  """
  @spec circle(Cauldron2D.Raster.t(), coord(), non_neg_integer(), Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def circle(raster, arg, radius, color), do: FrenchCurve.Draw.circle(raster, arg, radius, color)

  @doc """
  Fills a disc of `radius` pixels around the centre `{cx, cy}`.

  `radius` must be a non-negative integer.
  """
  @spec fill_circle(Cauldron2D.Raster.t(), coord(), non_neg_integer(), Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def fill_circle(raster, arg, radius, color),
    do: FrenchCurve.Draw.fill_circle(raster, arg, radius, color)

  @doc """
  Fills vertical columns, each `{x, y_from, y_to}` with both ends inclusive and in either
  order.

  Columns may repeat an `x` or overlap; the union is filled. The columns are written as
  horizontal spans in one raster update.
  """
  @spec fill_columns(Cauldron2D.Raster.t(), [column()], Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def fill_columns(raster, columns, color),
    do: FrenchCurve.Draw.fill_columns(raster, columns, color)

  @doc """
  Fills the polygon whose corners are `points`, edges included.

  The polygon is closed from the last point back to the first. Points may be fractional;
  a pixel is filled when its centre lies inside, using the even-odd rule, and the outline
  is drawn as well so thin shapes are never lost. Fewer than three points draw as a
  polyline.
  """
  @spec fill_polygon(Cauldron2D.Raster.t(), [{number(), number()}], Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def fill_polygon(raster, points, color),
    do: FrenchCurve.Draw.fill_polygon(raster, points, color)

  @doc """
  Fills every pixel of the rectangle spanned by two opposite corners, edges included.

  Both corners are inclusive and may be given in any order.
  """
  @spec fill_rect(Cauldron2D.Raster.t(), coord(), coord(), Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def fill_rect(raster, arg1, arg2, color),
    do: FrenchCurve.Draw.fill_rect(raster, arg1, arg2, color)

  @doc """
  Draws a one-pixel-wide line between the two endpoints, both inclusive.

  Handles any direction, including purely horizontal, vertical and single-point lines.
  """
  @spec line(Cauldron2D.Raster.t(), coord(), coord(), Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def line(raster, from, to, color), do: FrenchCurve.Draw.line(raster, from, to, color)

  @doc """
  Returns the pixels of the one-pixel-wide line between two endpoints, both inclusive,
  in walking order from `from` to `to`.
  """
  @spec line_points(coord(), coord()) :: [coord()]
  def line_points(arg1, arg2), do: FrenchCurve.Draw.line_points(arg1, arg2)

  @doc """
  Draws a connected run of line segments through `points` in order.

  A single point plots that pixel and an empty list leaves the raster unchanged. Points
  are not closed back to the first one; pass the first point again to close the shape.
  """
  @spec polyline(Cauldron2D.Raster.t(), [coord()], Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def polyline(raster, points, color), do: FrenchCurve.Draw.polyline(raster, points, color)

  @doc """
  Draws the four edges of the rectangle spanned by two opposite corners.

  Both corners are inclusive and may be given in any order. The interior is untouched.
  """
  @spec rect(Cauldron2D.Raster.t(), coord(), coord(), Cauldron2D.Raster.color()) ::
          Cauldron2D.Raster.t()
  def rect(raster, arg1, arg2, color), do: FrenchCurve.Draw.rect(raster, arg1, arg2, color)
end
