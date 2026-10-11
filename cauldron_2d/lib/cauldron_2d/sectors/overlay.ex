defmodule Cauldron2D.Sectors.Overlay do
  @moduledoc """
  A picture drawn flat on the frame, stretched to a rectangle: a held weapon, a status
  bar, a face, a menu.

      frame
      |> Frame.columns(pictures, Overlay.columns(pictures, gun, {96.0, 120.0, 128.0, 80.0}, 0))

  The rectangle is `{x, y, width, height}` in frame pixels, fractions allowed, the picture
  filling it exactly. Transparent texels are skipped. `light` is the light table every
  texel goes through. Options: `flip: true` mirrors the picture; `shimmer: true` draws it as
  a blur of what is beneath, through `light`.
  """

  alias Cauldron2D.Sectors.{Frame, Pictures}

  @doc "The column records that draw picture `id` into `rect`."
  @spec columns(
          Pictures.t(),
          non_neg_integer(),
          {number(), number(), number(), number()},
          non_neg_integer(),
          keyword()
        ) ::
          [binary()]
  def columns(%Pictures{} = pictures, id, {x, y, width, height}, light, opts \\ []) do
    {picture_width, picture_height} = Pictures.size(pictures, id)
    scale_x = width / picture_width
    scale_y = height / picture_height
    first = ceil_cell(x)
    last = ceil_cell(x + width) - 1
    top = ceil_cell(y)
    bottom = ceil_cell(y + height) - 1
    flip? = Keyword.get(opts, :flip, false)

    for column <- first..last//1, top <= bottom do
      u = floor((column + 0.5 - x) / scale_x)
      u = if flip?, do: picture_width - 1 - u, else: u
      v = (top + 0.5 - y) / scale_y

      Frame.column(column, {top, bottom}, id, {u, v, 1.0 / scale_y}, light,
        masked: true,
        shimmer: Keyword.get(opts, :shimmer, false)
      )
    end
  end

  defp ceil_cell(value), do: (value - 0.5) |> Float.ceil() |> trunc()
end
