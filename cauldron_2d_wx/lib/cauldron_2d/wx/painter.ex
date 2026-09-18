defmodule Cauldron2D.Wx.Painter do
  @moduledoc """
  Where everything goes on a canvas: the map's tiles around the focus and the movers, as
  sheet indices at pixel positions, for a frame and map in the shapes `Cauldron2D.Net.Wire`
  gives.

      Cauldron2D.Wx.Painter.blits(frame, map, {width, height}, scale)

  The focus sits at the centre of the canvas, at a map's edge and past it alike; a map
  that wraps repeats around it. `scale` is the pixel size of a tile.
  """

  @type frame :: %{focus: {number(), number()}, movers: [{non_neg_integer(), number(), number()}]}
  @type map_layer :: %{
          width: pos_integer(),
          height: pos_integer(),
          wrap: boolean(),
          rows: [[non_neg_integer()]]
        }
  @type blit :: {non_neg_integer(), integer(), integer()}

  @doc "The world position at the canvas's top-left corner."
  @spec origin(frame(), map_layer(), {pos_integer(), pos_integer()}, pos_integer()) ::
          {float(), float()}
  def origin(%{focus: {fx, fy}}, _map, {width, height}, scale),
    do: {fx - width / scale / 2, fy - height / scale / 2}

  @doc "Every tile and mover in view, bottom to top, as `{index, x, y}` in pixels."
  @spec blits(frame(), map_layer(), {pos_integer(), pos_integer()}, pos_integer()) :: [blit()]
  def blits(frame, map, {width, height} = size, scale) do
    {ox, oy} = origin(frame, map, size, scale)
    view_w = width / scale
    view_h = height / scale

    tiles(map, {ox, oy}, {view_w, view_h}, scale, fn _index -> true end) ++
      movers(frame.movers, map, {ox, oy}, {view_w, view_h}, scale)
  end

  @doc "The tiles in view whose index is one of `indices`, as `{index, x, y}` in pixels: the cells a layer left out."
  @spec cell_blits(
          frame(),
          map_layer(),
          {pos_integer(), pos_integer()},
          pos_integer(),
          MapSet.t()
        ) :: [blit()]
  def cell_blits(_frame, _map, _size, _scale, %MapSet{map: empty}) when map_size(empty) == 0,
    do: []

  def cell_blits(frame, map, {width, height} = size, scale, indices) do
    tiles(
      map,
      origin(frame, map, size, scale),
      {width / scale, height / scale},
      scale,
      &MapSet.member?(indices, &1)
    )
  end

  defp tiles(map, {ox, oy}, {view_w, view_h}, scale, wanted?) do
    for y <- floor(oy)..ceil(oy + view_h),
        x <- floor(ox)..ceil(ox + view_w),
        index = tile(map, x, y),
        index > 0,
        wanted?.(index),
        do: {index, px(x - ox, scale), px(y - oy, scale)}
  end

  @doc """
  Every tile of the map once, as `{index, x, y}` in pixels from the map's top-left
  corner: what a layer of the whole map is drawn from. `except:` is a set of indices to
  leave out, for cells drawn every frame instead.
  """
  @spec layer_blits(map_layer(), pos_integer(), keyword()) :: [blit()]
  def layer_blits(map, scale, opts \\ []) do
    except = Keyword.get(opts, :except, MapSet.new())

    for {row, y} <- Enum.with_index(map.rows),
        {index, x} <- Enum.with_index(row),
        index > 0,
        not MapSet.member?(except, index),
        do: {index, x * scale, y * scale}
  end

  @doc "Where a layer of the whole map goes on the canvas for `frame`: one pixel offset, or every copy in view of a wrapping map."
  @spec layer_offsets(frame(), map_layer(), {pos_integer(), pos_integer()}, pos_integer()) :: [
          {integer(), integer()}
        ]
  def layer_offsets(frame, map, {width, height} = size, scale) do
    {ox, oy} = origin(frame, map, size, scale)

    copies =
      if map.wrap,
        do:
          for(dx <- [0, map.width, -map.width], dy <- [0, map.height, -map.height], do: {dx, dy}),
        else: [{0, 0}]

    for {dx, dy} <- copies,
        x = px(dx - ox, scale),
        y = px(dy - oy, scale),
        x < width and y < height and x + map.width * scale > 0 and y + map.height * scale > 0,
        do: {x, y}
  end

  @doc "The movers in view, as `{index, x, y}` in pixels."
  @spec mover_blits(frame(), map_layer(), {pos_integer(), pos_integer()}, pos_integer()) :: [
          blit()
        ]
  def mover_blits(frame, map, {width, height} = size, scale) do
    movers(
      frame.movers,
      map,
      origin(frame, map, size, scale),
      {width / scale, height / scale},
      scale
    )
  end

  @doc "Where a label at world position `at` lands on the canvas, in pixels: once, or on every copy in view of a wrapping map."
  @spec label_blits(
          frame(),
          map_layer(),
          {pos_integer(), pos_integer()},
          pos_integer(),
          {number(), number()}
        ) :: [{integer(), integer()}]
  def label_blits(frame, map, {width, height} = size, scale, {x, y}) do
    for {_index, px, py} <-
          movers(
            [{0, x, y}],
            map,
            origin(frame, map, size, scale),
            {width / scale, height / scale},
            scale
          ),
        px < width,
        py < height,
        do: {px, py}
  end

  @doc "The world position under a canvas point."
  @spec world_at(
          frame(),
          map_layer(),
          {pos_integer(), pos_integer()},
          pos_integer(),
          {number(), number()}
        ) :: {float(), float()}
  def world_at(frame, map, size, scale, {cx, cy}) do
    {ox, oy} = origin(frame, map, size, scale)
    {ox + cx / scale, oy + cy / scale}
  end

  @doc "The focus that keeps the world under canvas point `{cx, cy}` there when the tile goes from `from` to `to` pixels."
  @spec zoom_about(
          frame(),
          map_layer(),
          {pos_integer(), pos_integer()},
          pos_integer(),
          pos_integer(),
          {number(), number()}
        ) :: {float(), float()}
  def zoom_about(frame, map, {width, height} = size, from, to, {cx, cy}) do
    {wx, wy} = world_at(frame, map, size, from, {cx, cy})
    {wx - cx / to + width / to / 2, wy - cy / to + height / to / 2}
  end

  defp tile(%{wrap: true} = map, x, y),
    do: map.rows |> Enum.at(Integer.mod(y, map.height)) |> Enum.at(Integer.mod(x, map.width))

  defp tile(map, x, y) when x >= 0 and y >= 0 and x < map.width and y < map.height,
    do: map.rows |> Enum.at(y) |> Enum.at(x)

  defp tile(_map, _x, _y), do: 0

  defp movers(movers, map, {ox, oy}, {view_w, view_h}, scale) do
    offsets =
      if map.wrap,
        do:
          for(dx <- [0, map.width, -map.width], dy <- [0, map.height, -map.height], do: {dx, dy}),
        else: [{0, 0}]

    for {index, x, y} <- movers,
        {dx, dy} <- offsets,
        px = x + dx - ox,
        py = y + dy - oy,
        px > -1 and py > -1 and px < view_w and py < view_h do
      {index, px(px, scale), px(py, scale)}
    end
  end

  defp px(tiles, scale), do: round(tiles * scale)
end
