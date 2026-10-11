defmodule Cauldron2D.GameMaker.Shapes do
  @moduledoc """
  GameMaker's drawn shapes as pictures, in white, to be tinted by a draw list item's
  `:blend` and `:alpha`.

  `{:ellipse, {width, height}, fill}` is `draw_ellipse(x1, y1, x1 + width, y1 + height,
  outline)` placed at `{x1, y1}`: the polygon of the runtime's circle precision (24
  points, `draw_set_circle_precision`'s default) inscribed in the box, `fill` `:filled`
  covering every pixel whose centre lies inside it, `:outline` its edges one pixel wide.

      item = %{picture: {:ellipse, {200, 200}, :filled}, position: {0, 0}, blend: {255, 255, 255}}

  `Cauldron2D.GameMaker.Surfaces.lookup/2` resolves these pictures.
  """

  alias FrenchCurve.Raster

  @precision 24
  @white {255, 255, 255, 255}

  @type fill :: :filled | :outline
  @type key :: {:ellipse, {number(), number()}, fill()}

  @doc "The raster of shape `key`, `nil` for a box without area."
  @spec raster(key()) :: Raster.t() | nil
  def raster({:ellipse, {width, height}, _fill}) when width <= 0 or height <= 0, do: nil

  def raster({:ellipse, {width, height}, fill}) do
    columns = ceil(width)
    rows = ceil(height)
    corners = ellipse_points(width, height)
    covered = covered(fill, corners, columns, rows)

    pixels =
      for row <- 0..(rows - 1), column <- 0..(columns - 1), into: <<>> do
        if MapSet.member?(covered, {column, row}), do: rgba(@white), else: <<0, 0, 0, 0>>
      end

    Raster.from_rgba(columns, rows, pixels)
  end

  defp ellipse_points(width, height) do
    {radius_x, radius_y} = {width / 2, height / 2}

    for step <- 0..(@precision - 1) do
      angle = step * 2 * :math.pi() / @precision
      {radius_x + radius_x * :math.cos(angle), radius_y + radius_y * :math.sin(angle)}
    end
  end

  defp covered(:filled, corners, columns, rows) do
    edges = edges(corners)

    for row <- 0..(rows - 1),
        column <- 0..(columns - 1),
        inside?(edges, {column + 0.5, row + 0.5}),
        into: MapSet.new(),
        do: {column, row}
  end

  defp covered(:outline, corners, columns, rows) do
    for {from, to} <- edges(corners),
        pixel <- line(from, to),
        within?(pixel, columns, rows),
        into: MapSet.new(),
        do: pixel
  end

  defp edges(corners), do: Enum.zip(corners, tl(corners) ++ [hd(corners)])

  defp inside?(edges, point) do
    sides = Enum.map(edges, &side(&1, point))
    Enum.all?(sides, &(&1 >= 0)) or Enum.all?(sides, &(&1 <= 0))
  end

  defp side({{x1, y1}, {x2, y2}}, {x, y}), do: (x2 - x1) * (y - y1) - (y2 - y1) * (x - x1)

  defp line({x1, y1}, {x2, y2}) do
    steps = max(ceil(max(abs(x2 - x1), abs(y2 - y1))), 1)

    for step <- 0..steps do
      fraction = step / steps
      {floor(x1 + (x2 - x1) * fraction), floor(y1 + (y2 - y1) * fraction)}
    end
  end

  defp within?({column, row}, columns, rows),
    do: column >= 0 and row >= 0 and column < columns and row < rows

  defp rgba({red, green, blue, alpha}), do: <<red, green, blue, alpha>>
end
