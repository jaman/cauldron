defmodule Cauldron2D.Grid.Coarse.Space do
  @moduledoc """
  Positions on a grid of `width` by `height` tiles whose opposite edges join when
  `wrap?`, as `Cauldron2D.Grid.Coarse` measures them. Any map with those three keys is a
  space.

      Space.delta(%{width: 10, height: 10, wrap?: true}, {9.5, 0.5}, {0.5, 0.5})
      #=> {1.0, 0.0}
  """

  @type t :: %{
          required(:width) => pos_integer(),
          required(:height) => pos_integer(),
          required(:wrap?) => boolean(),
          optional(atom()) => term()
        }

  @doc "How far `to` lies from `from` on each axis, the short way across joined edges."
  @spec delta(t(), {number(), number()}, {number(), number()}) :: {number(), number()}
  def delta(space, {x1, y1}, {x2, y2}),
    do: {axis(x2 - x1, space.width, space.wrap?), axis(y2 - y1, space.height, space.wrap?)}

  @doc "The place of `point` nearest `reference`: `point` itself, or on a wrapping grid the copy of it across the edges closest to `reference`."
  @spec near(t(), {number(), number()}, {number(), number()}) :: {number(), number()}
  def near(space, {rx, ry} = reference, point) do
    {dx, dy} = delta(space, reference, point)
    {rx + dx, ry + dy}
  end

  @doc "The straight distance from `a` to `b`, the short way across joined edges."
  @spec distance(t(), {number(), number()}, {number(), number()}) :: float()
  def distance(space, a, b) do
    {dx, dy} = delta(space, a, b)
    :math.sqrt(dx * dx + dy * dy)
  end

  @doc "The tile holding `point`, brought onto the grid when it wraps, or nil when it lies off a grid that does not."
  @spec tile(t(), {number(), number()}) :: {integer(), integer()} | nil
  def tile(%{wrap?: true} = space, {x, y}),
    do: {Integer.mod(floor(x), space.width), Integer.mod(floor(y), space.height)}

  def tile(space, {x, y}) do
    {tx, ty} = {floor(x), floor(y)}
    if tx >= 0 and ty >= 0 and tx < space.width and ty < space.height, do: {tx, ty}
  end

  defp axis(difference, extent, true), do: difference - extent * round(difference / extent)
  defp axis(difference, _extent, false), do: difference
end
