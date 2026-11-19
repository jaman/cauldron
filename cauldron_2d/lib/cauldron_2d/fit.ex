defmodule Cauldron2D.Fit do
  @moduledoc """
  Fitting a frame of a fixed shape into a picture of another, with bars on the sides or
  above and below.

  A `:picture` scene that names its `:frame` — the shape the game's screen is shown at,
  `{320, 240}` for a 320×200 VGA screen shown 4:3 — draws its screen into the rectangle
  `letterbox/3` gives, and the surface maps the pointer into that same rectangle, so a
  game reads the pointer as a point of its own screen.

      Cauldron2D.Fit.letterbox({400, 200}, 1.0, {320, 240})
      #=> {66, 0, 267, 200}
  """

  @doc """
  The rectangle `{x, y, width, height}` of a `{width, height}` picture, whose pixels are
  `aspect` times as wide as they are tall, that shows a frame of shape `frame` as large
  as it fits, centred. `aspect` is the one a `:picture` function is given.
  """
  @spec letterbox({pos_integer(), pos_integer()}, number(), {number(), number()}) ::
          {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()}
  def letterbox({width, height}, aspect, {frame_width, frame_height}) do
    shape = frame_width / frame_height
    shown = width * aspect / height

    {fitted_width, fitted_height} =
      if shown > shape,
        do: {max(round(height * shape / aspect), 1), height},
        else: {width, max(round(width * aspect / shape), 1)}

    {div(width - fitted_width, 2), div(height - fitted_height, 2), fitted_width, fitted_height}
  end

  @doc """
  The point of the frame under picture fraction `{fx, fy}` (as a `:picture` surface
  reports the pointer), as fractions of the letterboxed frame, or `nil` outside it.
  """
  @spec within(
          {number(), number()},
          {pos_integer(), pos_integer()},
          number(),
          {number(), number()}
        ) ::
          {float(), float()} | nil
  def within({fx, fy}, {width, height} = size, aspect, frame) do
    {x, y, fitted_width, fitted_height} = letterbox(size, aspect, frame)
    u = (fx * width - x) / fitted_width
    v = (fy * height - y) / fitted_height
    if u >= 0 and u < 1 and v >= 0 and v < 1, do: {u, v}, else: nil
  end
end
