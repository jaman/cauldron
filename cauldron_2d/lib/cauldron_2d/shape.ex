defmodule Cauldron2D.Shape do
  @moduledoc """
  A solid shape placed in world pixels, for collision.

  `form` is `{:rectangle, width, height}`, every pixel solid, or `{:mask, mask}`, the
  solid pixels of a `Cauldron2D.Mask`. It is placed as a picture is drawn by
  `Cauldron2D.Blend.draw/6`: its `origin` lands on `position`, scaled per axis by
  `scale` (negative mirrors) and turned by `angle` degrees counter-clockwise.

      shape = Cauldron2D.Shape.new({:mask, mask}, {120, 88}, origin: {9, 28}, scale: {-1, 1})
      Cauldron2D.Shape.contains?(shape, {121.5, 80.5})

  A world point is inside the shape when the shape's pixel it falls on is solid; a
  pixel covers `[x, x + 1)` by `[y, y + 1)` of the shape's own pixels.
  """

  alias Cauldron2D.Mask
  alias Cauldron2D.Turn

  @enforce_keys [:form, :position]
  defstruct [:form, :position, origin: {0, 0}, scale: {1, 1}, cos: 1, sin: 0]

  @type form :: {:rectangle, number(), number()} | {:mask, Mask.t()}
  @type t :: %__MODULE__{
          form: form(),
          position: {number(), number()},
          origin: {number(), number()},
          scale: {number(), number()},
          cos: number(),
          sin: number()
        }

  @doc "`form` placed at `position`, with `:origin`, `:scale` and `:angle` as above."
  @spec new(form(), {number(), number()}, keyword()) :: t()
  def new(form, position, opts \\ []) do
    {cos, sin} = Turn.cos_sin(Keyword.get(opts, :angle, 0))

    %__MODULE__{
      form: form,
      position: position,
      origin: Keyword.get(opts, :origin, {0, 0}),
      scale: Keyword.get(opts, :scale, {1, 1}),
      cos: cos,
      sin: sin
    }
  end

  @doc "Whether the world point `{x, y}` is inside the shape."
  @spec contains?(t(), {number(), number()}) :: boolean()
  def contains?(%__MODULE__{scale: {scale_x, scale_y}}, _point)
      when scale_x == 0 or scale_y == 0,
      do: false

  def contains?(%__MODULE__{} = shape, point), do: solid?(shape.form, local(shape, point))

  @doc """
  The world rectangle `{left, top, right, bottom}` the shape lies within; `nil` for a
  shape scaled to nothing.
  """
  @spec bounds(t()) :: {number(), number(), number(), number()} | nil
  def bounds(%__MODULE__{scale: {scale_x, scale_y}}) when scale_x == 0 or scale_y == 0,
    do: nil

  def bounds(%__MODULE__{} = shape) do
    {width, height} = size(shape.form)

    {xs, ys} =
      [{0, 0}, {width, 0}, {0, height}, {width, height}]
      |> Enum.map(&world(shape, &1))
      |> Enum.unzip()

    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  defp size({:rectangle, width, height}), do: {width, height}
  defp size({:mask, %Mask{width: width, height: height}}), do: {width, height}

  defp world(%__MODULE__{} = shape, {u, v}) do
    {origin_x, origin_y} = shape.origin
    {scale_x, scale_y} = shape.scale
    {x, y} = shape.position
    dx = (u - origin_x) * scale_x
    dy = (v - origin_y) * scale_y
    {x + dx * shape.cos + dy * shape.sin, y - dx * shape.sin + dy * shape.cos}
  end

  defp local(%__MODULE__{} = shape, {px, py}) do
    {origin_x, origin_y} = shape.origin
    {scale_x, scale_y} = shape.scale
    {x, y} = shape.position
    rx = px - x
    ry = py - y

    {(rx * shape.cos - ry * shape.sin) / scale_x + origin_x,
     (rx * shape.sin + ry * shape.cos) / scale_y + origin_y}
  end

  defp solid?({:rectangle, width, height}, {u, v}),
    do: u >= 0 and v >= 0 and u < width and v < height

  defp solid?({:mask, %Mask{} = mask}, {u, v}) when u >= 0 and v >= 0,
    do: Mask.set?(mask, {floor(u), floor(v)})

  defp solid?({:mask, %Mask{}}, _point), do: false
end
