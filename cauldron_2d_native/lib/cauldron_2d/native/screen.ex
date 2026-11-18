defmodule Cauldron2D.Native.Screen do
  @moduledoc """
  Where the picture goes on a phone's screen. The picture is drawn `scale` screen
  pixels to one of its own: the screen's pixels a point times `:point_size` (the points
  a picture pixel takes, default `0.75`), rounded, at least `1`. A picture pixel is so
  about the same size under the eye on a phone and a tablet, and a tablet's larger
  screen shows more of the world. The pane is the tiles that picture holds at zoom 1.
  The app shows it centred, scaled to fit by whole pixels (`CauldronNative.present/3`),
  and `fraction/3` maps a touch back to fractions of it, as a mouse's `:at` is given.
  """

  @default_point_size 0.75

  @doc "Screen pixels a picture pixel for a screen `%{scale}` (pixels a point), given `point_size`."
  @spec scale(map(), number() | nil) :: pos_integer()
  def scale(%{scale: pixels_a_point}, point_size),
    do: max(1, round(pixels_a_point * (point_size || @default_point_size)))

  @doc "The tiles across and down the pane shows at zoom 1, for tiles `tile` pixels wide."
  @spec pane(map(), pos_integer(), pos_integer()) :: {pos_integer(), pos_integer()}
  def pane(%{width: width, height: height}, tile, scale),
    do: {max(1, div(width, tile * scale)), max(1, div(height, tile * scale))}

  @doc """
  The touch at `{x, y}` (screen pixels) as fractions of a picture `{width, height}`
  shown on the screen, or `nil` when it falls outside the picture.
  """
  @spec fraction(map(), {pos_integer(), pos_integer()}, {number(), number()}) ::
          {float(), float()} | nil
  def fraction(screen, {picture_width, picture_height}, {x, y}) do
    {left, top, shown_width, shown_height} = shown(screen, {picture_width, picture_height})
    fx = (x - left) / shown_width
    fy = (y - top) / shown_height
    if fx >= 0 and fx <= 1 and fy >= 0 and fy <= 1, do: {fx, fy}
  end

  @doc "The rectangle `{left, top, width, height}` the picture takes on the screen, in pixels."
  @spec shown(map(), {pos_integer(), pos_integer()}) :: {float(), float(), float(), float()}
  def shown(%{width: width, height: height}, {picture_width, picture_height}) do
    fit = min(width / picture_width, height / picture_height)
    factor = if fit >= 1, do: Float.floor(fit / 1), else: fit
    shown_width = picture_width * factor
    shown_height = picture_height * factor
    {(width - shown_width) / 2, (height - shown_height) / 2, shown_width, shown_height}
  end
end
