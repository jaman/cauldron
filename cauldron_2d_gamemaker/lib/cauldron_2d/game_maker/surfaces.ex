defmodule Cauldron2D.GameMaker.Surfaces do
  @moduledoc """
  Surfaces, as GameMaker's `surface_*` functions make them: rasters code draws onto,
  kept in the world by id until freed, across rooms.

      {world, canvas} = Surfaces.create(world, 320, 200)
      world = Surfaces.draw(world, canvas, [%{picture: {:sprite, 3, 0}, position: {10, 10}}])
      world = Draw.item(world, Surfaces.item(world, canvas, {x, y}))

  Drawing onto a surface renders at once, as `surface_set_target` does: `draw/3` takes
  draw list items in the surface's own pixels and draws them over what is there, with
  the world's `pictures` lookup, and `{:surface, id}` naming another surface, each blended
  as GameMaker blends onto a surface — its blend factors applied to the alpha channel as
  well as the colours (`Cauldron2D.Blend`'s `{:gamemaker, mode}`). `item/4`
  is a draw list item showing a surface; a frame shows it by looking `{:surface, id}`
  up in the world's `surfaces` (`lookup/2`). `draw/4` takes `:write`, the channels
  drawing may change, as `draw_set_colour_write_enable` sets them.

  `lookup/2` also gives `Cauldron2D.GameMaker.Shapes`' pictures, such as
  `{:ellipse, {width, height}, :filled}`, and a tile layer's picture
  (`Cauldron2D.GameMaker.TileLayers`).
  """

  alias Cauldron2D.DrawList
  alias Cauldron2D.GameMaker.{Shapes, TileLayers, World}
  alias FrenchCurve.Raster

  @type id :: non_neg_integer()

  @doc "The world with a new surface `width` × `height`, clear; `{world, id}`."
  @spec create(World.t(), pos_integer(), pos_integer()) :: {World.t(), id()}
  def create(%World{surfaces: %{rasters: surfaces, next: id}} = world, width, height) do
    raster = Raster.new(round(width), round(height), background: {0, 0, 0, 0})
    {%{world | surfaces: %{rasters: Map.put(surfaces, id, raster), next: id + 1}}, id}
  end

  @doc "Every surface's raster, by id."
  @spec rasters(World.t()) :: %{id() => Raster.t()}
  def rasters(%World{surfaces: %{rasters: surfaces}}), do: surfaces

  @doc "Whether surface `id` exists."
  @spec exists?(World.t(), id() | nil) :: boolean()
  def exists?(%World{surfaces: %{rasters: surfaces}}, id), do: Map.has_key?(surfaces, id)

  @doc "The world without surface `id`."
  @spec free(World.t(), id()) :: World.t()
  def free(%World{surfaces: %{rasters: surfaces}} = world, id),
    do: put_rasters(world, Map.delete(surfaces, id))

  @doc "Surface `id`'s size `{width, height}`."
  @spec size(World.t(), id()) :: {pos_integer(), pos_integer()}
  def size(%World{surfaces: %{rasters: surfaces}}, id),
    do: Raster.dimensions(Map.fetch!(surfaces, id))

  @doc "The world with surface `id` filled with `colour` `{r, g, b}` at `alpha` (`draw_clear_alpha`)."
  @spec clear(World.t(), id(), {byte(), byte(), byte()}, number()) :: World.t()
  def clear(%World{} = world, id, {red, green, blue}, alpha) do
    {width, height} = size(world, id)
    raster = Raster.new(width, height, background: {red, green, blue, round(alpha * 255)})
    put_rasters(world, Map.put(rasters(world), id, raster))
  end

  @doc """
  The world with surface `source`'s pixels put on surface `destination` with their
  top-left corner at `{x, y}`, replacing what was there, colour and alpha alike
  (`surface_copy(destination, x, y, source)`); what falls outside `destination` is
  left out.
  """
  @spec copy(World.t(), id(), {integer(), integer()}, id()) :: World.t()
  def copy(%World{surfaces: %{rasters: surfaces}} = world, destination, {x, y}, source) do
    target = Map.fetch!(surfaces, destination)
    from = Map.fetch!(surfaces, source)
    {width, height} = Raster.dimensions(target)
    {from_width, from_height} = Raster.dimensions(from)
    left = max(round(x), 0)
    right = min(round(x) + from_width, width)
    top = max(round(y), 0)
    bottom = min(round(y) + from_height, height)

    if right > left and bottom > top do
      piece = Raster.crop(from, {left - round(x), top - round(y)}, {right - left, bottom - top})
      put_rasters(world, Map.put(surfaces, destination, pasted(target, piece, {left, top})))
    else
      world
    end
  end

  defp pasted(target, piece, {left, top}) do
    {width, height} = Raster.dimensions(target)
    {piece_width, piece_height} = Raster.dimensions(piece)
    pixels = Raster.to_rgba_binary(target)
    piece_pixels = Raster.to_rgba_binary(piece)
    stride = width * 4
    right = left + piece_width
    bottom = top + piece_height

    rows =
      for row <- 0..(piece_height - 1)//1 do
        line = (top + row) * stride

        [
          binary_part(pixels, line, left * 4),
          binary_part(piece_pixels, row * piece_width * 4, piece_width * 4),
          binary_part(pixels, line + right * 4, (width - right) * 4)
        ]
      end

    Raster.from_rgba(
      width,
      height,
      IO.iodata_to_binary([
        binary_part(pixels, 0, top * stride),
        rows,
        binary_part(pixels, bottom * stride, (height - bottom) * stride)
      ])
    )
  end

  @doc """
  The world with `items`, in surface `id`'s pixels, drawn over surface `id`. Option
  `:write` `{red, green, blue, alpha}`, each `true` or `false`, names the channels the
  drawing changes; the others keep what the surface held
  (`draw_set_colour_write_enable`). Default: all four.
  """
  @spec draw(World.t(), id(), [DrawList.item()], keyword()) :: World.t()
  def draw(world, id, items, opts \\ [])

  def draw(%World{} = world, _id, [], _opts), do: world

  def draw(%World{surfaces: %{rasters: surfaces}} = world, id, items, opts) do
    target = Map.fetch!(surfaces, id)
    blended = Enum.map(items, &Map.put(&1, :mode, {:gamemaker, Map.get(&1, :mode, :over)}))
    pictures = Map.new(blended, &{&1.picture, lookup(world, &1.picture)})

    case covered(blended, pictures, Raster.dimensions(target)) do
      nil ->
        world

      {left, top, width, height} ->
        under = Raster.crop(target, {left, top}, {width, height})

        drawn =
          DrawList.render(blended, {width, height}, &Map.fetch!(pictures, &1),
            view: {left, top},
            background: under
          )

        written = masked(under, drawn, Keyword.get(opts, :write, {true, true, true, true}))
        put_rasters(world, Map.put(surfaces, id, pasted(target, written, {left, top})))
    end
  end

  defp covered(items, pictures, size) do
    items
    |> Enum.flat_map(fn item ->
      case Map.fetch!(pictures, item.picture) do
        %Raster{} = picture -> [DrawList.extent(item, Raster.dimensions(picture))]
        nil -> []
      end
    end)
    |> Enum.reduce(nil, &union/2)
    |> clipped(size)
  end

  defp union(extent, nil), do: extent

  defp union({left, top, right, bottom}, {other_left, other_top, other_right, other_bottom}),
    do:
      {min(left, other_left), min(top, other_top), max(right, other_right),
       max(bottom, other_bottom)}

  defp clipped(nil, _size), do: nil

  defp clipped({left, top, right, bottom}, {width, height}) do
    from_x = max(floor(left) - 1, 0)
    from_y = max(floor(top) - 1, 0)
    to_x = min(ceil(right) + 1, width)
    to_y = min(ceil(bottom) + 1, height)
    if to_x > from_x and to_y > from_y, do: {from_x, from_y, to_x - from_x, to_y - from_y}
  end

  defp masked(_target, drawn, {true, true, true, true}), do: drawn

  defp masked(target, drawn, write) do
    {width, height} = Raster.dimensions(target)
    mask = write |> Tuple.to_list() |> Enum.map(&if(&1, do: 1, else: 0))

    pixels =
      for {<<old::binary-4>>, <<new::binary-4>>} <-
            Enum.zip(chunks(Raster.to_rgba_binary(target)), chunks(Raster.to_rgba_binary(drawn))),
          into: <<>>,
          do: pick(old, new, mask)

    Raster.from_rgba(width, height, pixels)
  end

  defp chunks(binary), do: for(<<pixel::binary-4 <- binary>>, do: pixel)

  defp pick(<<r0, g0, b0, a0>>, <<r1, g1, b1, a1>>, [wr, wg, wb, wa]),
    do: <<channel(r0, r1, wr), channel(g0, g1, wg), channel(b0, b1, wb), channel(a0, a1, wa)>>

  defp channel(_old, new, 1), do: new
  defp channel(old, _new, 0), do: old

  @doc """
  A draw list item showing surface `id` with its top-left corner at `{x, y}`. Options:
  those of a draw list item (`:scale`, `:angle`, `:blend`, `:alpha`, `:mode`, `:depth`)
  and `:origin`.
  """
  @spec item(World.t(), id(), {number(), number()}, keyword()) :: map()
  def item(%World{}, id, position, opts \\ []) do
    opts
    |> Map.new()
    |> Map.merge(%{picture: {:surface, id}, position: position})
    |> Map.put_new(:origin, {0, 0})
  end

  @doc """
  A draw list item showing the part `{left, top, width, height}` of surface `id`, its
  top-left corner at `{x, y}` (`draw_surface_part_ext`): the part is clipped to the
  surface, and what is clipped from its left and top moves the corner by as much, scaled.
  Options as `item/4`'s. `nil` when nothing of the part lies on the surface.
  """
  @spec part_item(
          World.t(),
          id(),
          {number(), number(), number(), number()},
          {number(), number()},
          keyword()
        ) :: map() | nil
  def part_item(%World{} = world, id, {left, top, width, height}, {x, y}, opts \\ []) do
    {surface_width, surface_height} = size(world, id)
    {scale_x, scale_y} = Keyword.get(opts, :scale, {1, 1})
    from_x = left |> round() |> max(0)
    from_y = top |> round() |> max(0)
    to_x = (left + width) |> round() |> min(surface_width)
    to_y = (top + height) |> round() |> min(surface_height)

    if to_x > from_x and to_y > from_y do
      shifted = {x + (from_x - left) * scale_x, y + (from_y - top) * scale_y}

      world
      |> item(id, shifted, opts)
      |> Map.put(:picture, {:surface_part, id, {from_x, from_y, to_x - from_x, to_y - from_y}})
    end
  end

  @doc "The raster for draw list picture `key`: a surface of the world's or part of one, a shape, or the world's own pictures."
  @spec lookup(World.t(), term()) :: Raster.t() | nil
  def lookup(%World{surfaces: %{rasters: surfaces}}, {:surface, id}), do: Map.get(surfaces, id)

  def lookup(
        %World{surfaces: %{rasters: surfaces}},
        {:surface_part, id, {left, top, width, height}}
      ) do
    case Map.get(surfaces, id) do
      nil -> nil
      raster -> Raster.crop(raster, {left, top}, {width, height})
    end
  end

  def lookup(%World{}, {:ellipse, _size, _fill} = shape), do: Shapes.raster(shape)

  def lookup(%World{} = world, {:tile_layer, _room, _layer, _blend} = key),
    do: TileLayers.raster(world.data, key, &lookup(world, &1))

  def lookup(%World{} = world, {:part, key, {left, top, width, height}}) do
    case lookup(world, key) do
      nil -> nil
      raster -> Raster.crop(raster, {left, top}, {width, height})
    end
  end

  def lookup(%World{pictures: nil}, _key), do: nil
  def lookup(%World{pictures: pictures}, key), do: pictures.(key)

  defp put_rasters(world, surfaces), do: put_in(world.surfaces.rasters, surfaces)
end
