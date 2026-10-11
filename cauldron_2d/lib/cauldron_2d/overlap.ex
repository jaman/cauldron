defmodule Cauldron2D.Overlap do
  @moduledoc """
  Whether placed shapes (`Cauldron2D.Shape`) touch each other, a point, a rectangle, a
  circle or a line.

  Two shapes overlap when some world pixel's centre, `{x + 0.5, y + 0.5}`, lies inside
  both. A rectangle query is a shape like any other; a circle covers the pixel centres
  within its radius; a line is sampled every half pixel along its length, both ends
  included.

      Cauldron2D.Overlap.shapes?(player, wall)
      Cauldron2D.Overlap.line?(wall, {0, 10}, {200, 10})
  """

  alias Cauldron2D.Shape

  @doc "Whether `first` and `second` share a pixel."
  @spec shapes?(Shape.t(), Shape.t()) :: boolean()
  def shapes?(%Shape{} = first, %Shape{} = second) do
    with {left, top, right, bottom} <- Shape.bounds(first),
         {other_left, other_top, other_right, other_bottom} <- Shape.bounds(second) do
      {max(left, other_left), max(top, other_top), min(right, other_right),
       min(bottom, other_bottom)}
      |> centres()
      |> Enum.any?(&(Shape.contains?(first, &1) and Shape.contains?(second, &1)))
    else
      nil -> false
    end
  end

  @doc "Whether the world point `{x, y}` is inside `shape`."
  @spec point?(Shape.t(), {number(), number()}) :: boolean()
  def point?(%Shape{} = shape, point), do: Shape.contains?(shape, point)

  @doc "Whether `shape` shares a pixel with the rectangle `{left, top, right, bottom}`."
  @spec rectangle?(Shape.t(), {number(), number(), number(), number()}) :: boolean()
  def rectangle?(%Shape{} = shape, {left, top, right, bottom})
      when right > left and bottom > top,
      do: shapes?(shape, Shape.new({:rectangle, right - left, bottom - top}, {left, top}))

  def rectangle?(%Shape{}, _rectangle), do: false

  @doc "Whether `shape` shares a pixel with the circle of `radius` around `{x, y}`."
  @spec circle?(Shape.t(), {number(), number()}, number()) :: boolean()
  def circle?(%Shape{} = shape, {x, y}, radius) do
    case Shape.bounds(shape) do
      nil ->
        false

      {left, top, right, bottom} ->
        {max(left, x - radius), max(top, y - radius), min(right, x + radius),
         min(bottom, y + radius)}
        |> centres()
        |> Enum.any?(fn {px, py} = centre ->
          (px - x) * (px - x) + (py - y) * (py - y) <= radius * radius and
            Shape.contains?(shape, centre)
        end)
    end
  end

  @doc "Whether the segment from `from` to `to` passes through `shape`."
  @spec line?(Shape.t(), {number(), number()}, {number(), number()}) :: boolean()
  def line?(%Shape{} = shape, {x1, y1} = from, {x2, y2}) do
    steps = ceil(:math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)) * 2)

    if steps == 0 do
      Shape.contains?(shape, from)
    else
      Enum.any?(0..steps, fn step ->
        Shape.contains?(shape, {x1 + (x2 - x1) * step / steps, y1 + (y2 - y1) * step / steps})
      end)
    end
  end

  defp centres({left, top, right, bottom}) do
    first_column = ceil(left - 0.5)
    last_column = ceil(right - 0.5) - 1
    first_row = ceil(top - 0.5)
    last_row = ceil(bottom - 0.5) - 1

    for row <- first_row..last_row//1,
        column <- first_column..last_column//1,
        do: {column + 0.5, row + 0.5}
  end
end
