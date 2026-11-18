defmodule Cauldron2D.Box do
  @moduledoc """
  Axis-aligned boxes in tile units, `{left, top, right, bottom}`, `y` growing downward:
  what a blow covers, what a body takes up, what a shot can touch. Edges that only meet
  do not overlap.

      blow = Cauldron2D.Box.around({hero.x + 1.0, hero.y - 1.2}, 0.6, 0.4)
      Cauldron2D.Box.overlap?(blow, Cauldron2D.BoxBody.box(goblin.body))
  """

  @type t :: {number(), number(), number(), number()}
  @type point :: {number(), number()}

  @doc "Whether boxes `a` and `b` share any area."
  @spec overlap?(t(), t()) :: boolean()
  def overlap?({l1, t1, r1, b1}, {l2, t2, r2, b2}),
    do: l1 < r2 and r1 > l2 and t1 < b2 and b1 > t2

  @doc "Whether `point` is strictly inside `box`."
  @spec contains?(t(), point()) :: boolean()
  def contains?({left, top, right, bottom}, {x, y}),
    do: x > left and x < right and y > top and y < bottom

  @doc "The box centred on `point`, `half` from the centre each way."
  @spec around(point(), number()) :: t()
  def around(point, half), do: around(point, half, half)

  @doc "The box centred on `point`, `half_width` across and `half_height` up and down."
  @spec around(point(), number(), number()) :: t()
  def around({x, y}, half_width, half_height),
    do: {x - half_width, y - half_height, x + half_width, y + half_height}

  @doc "The box of tile `{tx, ty}`."
  @spec tile({integer(), integer()}) :: t()
  def tile({tx, ty}), do: {tx, ty, tx + 1, ty + 1}

  @doc "The tiles `box` overlaps."
  @spec tiles(t()) :: [{integer(), integer()}]
  def tiles({left, top, right, bottom}) do
    for tx <- floor(left)..floor(right - 0.001)//1,
        ty <- floor(top + 0.001)..floor(bottom - 0.001)//1,
        do: {tx, ty}
  end
end
