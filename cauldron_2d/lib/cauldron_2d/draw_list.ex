defmodule Cauldron2D.DrawList do
  @moduledoc """
  A frame as a list of pictures placed in pixels, and the raster it draws.

  An item is a map:

    * `:picture` — any term naming a picture; `render/4` looks it up
    * `:position` — `{x, y}` in world pixels, where the picture's origin lands
    * `:depth` — greater depth is drawn first, further back; items of equal depth draw
      in list order. Default `0`
    * `:origin`, `:scale`, `:angle`, `:blend`, `:alpha`, `:mode` — as `Cauldron2D.Blend.draw/6`
      takes them

  Items hold only terms, so a draw list can be sent to another machine and drawn there
  from that machine's own pictures.

      items = [
        %{picture: {:sprite, 4, 0}, position: {120, 88}, origin: {9, 28}, depth: 0},
        %{picture: {:tile, 2, 17}, position: {96, 96}, depth: 100}
      ]

      raster = Cauldron2D.DrawList.render(items, {320, 200}, &MyGame.picture/1,
        view: {40, 0}, background: {20, 20, 40, 255})

  A `:picture` scene returns that raster from its function of the pane's size.
  """

  alias Cauldron2D.Render
  alias FrenchCurve.Raster

  @type item :: %{
          required(:picture) => term(),
          required(:position) => {number(), number()},
          optional(:depth) => number(),
          optional(:origin) => {number(), number()},
          optional(:scale) => {number(), number()},
          optional(:angle) => number(),
          optional(:blend) => {byte(), byte(), byte()},
          optional(:alpha) => number(),
          optional(:mode) => :over | :add | :subtract | {:gamemaker, :over | :add | :subtract}
        }

  @doc """
  The raster of `items`, `size` `{width, height}` pixels, each item's picture found by
  `pictures`, a function from the item's `:picture` to a `FrenchCurve.Raster` or `nil`
  (an item whose picture is `nil` is skipped).

  Options:

    * `:view` — `{x, y}`, the world pixel at the raster's top-left corner; default `{0, 0}`
    * `:zoom` — raster pixels per world pixel; default `1`
    * `:background` — `{r, g, b, a}` the raster starts as; default transparent
    * `:native`, `:bands` — as `Cauldron2D.Render.render/3` takes them

  Items that cannot reach the raster are left out before drawing.
  """
  @spec render([item()], {pos_integer(), pos_integer()}, (term() -> Raster.t() | nil), keyword()) ::
          Raster.t()
  def render(items, size, pictures, opts \\ []) do
    camera = {Keyword.get(opts, :view, {0, 0}), Keyword.get(opts, :zoom, 1)}

    operations =
      for item <- in_depth_order(items),
          %Raster{} = picture <- [pictures.(item.picture)],
          placement = placement(item, camera),
          reaches?(placement, Raster.dimensions(picture), size),
          do: {:sprite, picture, placement}

    Render.render(size, operations, Keyword.take(opts, [:background, :native, :bands]))
  end

  @doc "`items` in the order they are drawn: greatest depth first, ties in list order."
  @spec in_depth_order([item()]) :: [item()]
  def in_depth_order(items), do: Enum.sort_by(items, &(-Map.get(&1, :depth, 0)))

  defp placement(item, {{view_x, view_y}, zoom}) do
    {x, y} = item.position
    {scale_x, scale_y} = Map.get(item, :scale, {1, 1})

    item
    |> Map.take([:origin, :angle, :blend, :alpha, :mode])
    |> Map.merge(%{
      position: {(x - view_x) * zoom, (y - view_y) * zoom},
      scale: {scale_x * zoom, scale_y * zoom}
    })
  end

  @doc """
  `{left, top, right, bottom}`, a rectangle in `item`'s pixels that holds every pixel
  its picture, `size` `{width, height}`, can cover, whatever its scale and angle.
  """
  @spec extent(map(), {pos_integer(), pos_integer()}) :: {float(), float(), float(), float()}
  def extent(item, {width, height}) do
    {x, y} = item.position
    {origin_x, origin_y} = Map.get(item, :origin, {0, 0})
    {scale_x, scale_y} = Map.get(item, :scale, {1, 1})

    farthest =
      for {u, v} <- [{0, 0}, {width, 0}, {0, height}, {width, height}] do
        :math.sqrt((u - origin_x) * (u - origin_x) + (v - origin_y) * (v - origin_y))
      end

    reach = Enum.max(farthest) * max(abs(scale_x), abs(scale_y))
    {x - reach, y - reach, x + reach, y + reach}
  end

  defp reaches?(placement, size, {frame_width, frame_height}) do
    {left, top, right, bottom} = extent(placement, size)
    right > 0 and bottom > 0 and left < frame_width and top < frame_height
  end
end
