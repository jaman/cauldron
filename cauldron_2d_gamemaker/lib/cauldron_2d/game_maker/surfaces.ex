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

  Every change to a surface is kept as an operation until `take_ops/1` takes them, oldest
  first: `{:create, id, width, height}`, `{:free, id}`, `{:clear, id, colour, alpha}`,
  `{:copy, destination, {x, y}, source}` and `{:draw, id, items, opts}`. `replay/2`
  applies them to a `Cauldron2D.GameMaker.Surfaces.Mirror`, which then holds the same
  rasters as the world, and `snapshot/1` is the one operation, `{:rasters, rasters,
  next}`, that sets a mirror to a world's surfaces as they are. The functions here that
  read or change surfaces take a mirror in place of a world.

      {ops, world} = Surfaces.take_ops(world)
      mirror = Surfaces.replay(mirror, ops)
  """

  alias Cauldron2D.DrawList
  alias Cauldron2D.GameMaker.{Shapes, TileLayers, World}
  alias Cauldron2D.GameMaker.Surfaces.Mirror
  alias FrenchCurve.Raster

  @type id :: non_neg_integer()
  @type holder :: World.t() | Mirror.t()
  @type op ::
          {:create, id(), pos_integer(), pos_integer()}
          | {:free, id()}
          | {:clear, id(), {byte(), byte(), byte()}, number()}
          | {:copy, id(), {integer(), integer()}, id()}
          | {:draw, id(), [DrawList.item()], keyword()}
          | {:rasters, %{id() => Raster.t()}, non_neg_integer()}

  defguardp holder?(value) when is_struct(value, World) or is_struct(value, Mirror)

  @doc "The world with a new surface `width` × `height`, clear; `{world, id}`."
  @spec create(holder(), pos_integer(), pos_integer()) :: {holder(), id()}
  def create(%{surfaces: %{next: id}} = world, width, height) when holder?(world) do
    {created(world, id, round(width), round(height)), id}
  end

  defp created(world, id, width, height) do
    raster = Raster.new(width, height, background: {0, 0, 0, 0})

    world
    |> put_rasters(Map.put(rasters(world), id, raster))
    |> put_in([Access.key!(:surfaces), :next], max(world.surfaces.next, id + 1))
    |> recorded({:create, id, width, height})
  end

  @doc "Every surface's raster, by id."
  @spec rasters(holder()) :: %{id() => Raster.t()}
  def rasters(%{surfaces: %{rasters: surfaces}} = world) when holder?(world), do: surfaces

  @doc "Whether surface `id` exists."
  @spec exists?(holder(), id() | nil) :: boolean()
  def exists?(%{surfaces: %{rasters: surfaces}} = world, id) when holder?(world),
    do: Map.has_key?(surfaces, id)

  @doc "The world without surface `id`."
  @spec free(holder(), id()) :: holder()
  def free(%{surfaces: %{rasters: surfaces}} = world, id) when holder?(world),
    do: world |> put_rasters(Map.delete(surfaces, id)) |> recorded({:free, id})

  @doc "Surface `id`'s size `{width, height}`."
  @spec size(holder(), id()) :: {pos_integer(), pos_integer()}
  def size(%{surfaces: %{rasters: surfaces}} = world, id) when holder?(world),
    do: Raster.dimensions(Map.fetch!(surfaces, id))

  @doc "The world with surface `id` filled with `colour` `{r, g, b}` at `alpha` (`draw_clear_alpha`)."
  @spec clear(holder(), id(), {byte(), byte(), byte()}, number()) :: holder()
  def clear(world, id, {red, green, blue} = colour, alpha) when holder?(world) do
    {width, height} = size(world, id)
    raster = Raster.new(width, height, background: {red, green, blue, round(alpha * 255)})

    world
    |> put_rasters(Map.put(rasters(world), id, raster))
    |> recorded({:clear, id, colour, alpha})
  end

  @doc "The operations made on the surfaces since they were last taken, oldest first, and the world without them."
  @spec take_ops(holder()) :: {[op()], holder()}
  def take_ops(%{surfaces: surfaces} = world) when holder?(world) do
    {Enum.reverse(Map.get(surfaces, :ops, [])), put_in(world.surfaces[:ops], [])}
  end

  @doc "The operation that sets a mirror's surfaces to these, as they are now."
  @spec snapshot(holder()) :: op()
  def snapshot(%{surfaces: %{rasters: surfaces, next: next}} = world) when holder?(world),
    do: {:rasters, surfaces, next}

  @doc """
  `mirror` with `ops` applied in order, and none kept to be taken. An operation on a
  surface the mirror does not hold is passed over, as are those before the first
  `{:rasters, _, _}` of a mirror that has not yet had one.
  """
  @spec replay(holder(), [op()]) :: holder()
  def replay(mirror, ops) when holder?(mirror) and is_list(ops) do
    ops
    |> Enum.reduce(mirror, &replayed(&2, &1))
    |> put_in([Access.key!(:surfaces), :ops], [])
  end

  defp replayed(mirror, {:rasters, surfaces, next}),
    do: put_in(mirror.surfaces, %{rasters: surfaces, next: next, ops: []})

  defp replayed(mirror, {:create, id, width, height}), do: created(mirror, id, width, height)

  defp replayed(mirror, operation) do
    if Enum.all?(named(operation), &exists?(mirror, &1)),
      do: applied(mirror, operation),
      else: mirror
  end

  defp named({:copy, destination, _at, source}), do: [destination, source]
  defp named(operation), do: [elem(operation, 1)]

  defp applied(mirror, {:free, id}), do: free(mirror, id)
  defp applied(mirror, {:clear, id, colour, alpha}), do: clear(mirror, id, colour, alpha)

  defp applied(mirror, {:copy, destination, at, source}),
    do: copy(mirror, destination, at, source)

  defp applied(mirror, {:draw, id, items, opts}), do: draw(mirror, id, items, opts)

  defp recorded(%{surfaces: surfaces} = world, operation),
    do: %{world | surfaces: Map.update(surfaces, :ops, [operation], &[operation | &1])}

  @doc """
  The world with surface `source`'s pixels put on surface `destination` with their
  top-left corner at `{x, y}`, replacing what was there, colour and alpha alike
  (`surface_copy(destination, x, y, source)`); what falls outside `destination` is
  left out.
  """
  @spec copy(holder(), id(), {integer(), integer()}, id()) :: holder()
  def copy(%{surfaces: %{rasters: surfaces}} = world, destination, {x, y} = at, source)
      when holder?(world) do
    world = recorded(world, {:copy, destination, at, source})
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
  @spec draw(holder(), id(), [DrawList.item()], keyword()) :: holder()
  def draw(world, id, items, opts \\ [])

  def draw(world, _id, [], _opts) when holder?(world), do: world

  def draw(%{surfaces: %{rasters: surfaces}} = world, id, items, opts) when holder?(world) do
    world = recorded(world, {:draw, id, items, opts})
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
  @spec lookup(holder(), term()) :: Raster.t() | nil
  def lookup(%{surfaces: %{rasters: surfaces}} = world, {:surface, id}) when holder?(world),
    do: Map.get(surfaces, id)

  def lookup(
        %{surfaces: %{rasters: surfaces}} = world,
        {:surface_part, id, {left, top, width, height}}
      )
      when holder?(world) do
    case Map.get(surfaces, id) do
      nil -> nil
      raster -> Raster.crop(raster, {left, top}, {width, height})
    end
  end

  def lookup(world, {:ellipse, _size, _fill} = shape) when holder?(world),
    do: Shapes.raster(shape)

  def lookup(world, {:tile_layer, _room, _layer, _blend} = key) when holder?(world),
    do: TileLayers.raster(world.data, key, &lookup(world, &1))

  def lookup(world, {:part, key, {left, top, width, height}}) when holder?(world) do
    case lookup(world, key) do
      nil -> nil
      raster -> Raster.crop(raster, {left, top}, {width, height})
    end
  end

  def lookup(%{pictures: nil} = world, _key) when holder?(world), do: nil
  def lookup(%{pictures: pictures} = world, key) when holder?(world), do: pictures.(key)

  defp put_rasters(world, surfaces), do: put_in(world.surfaces.rasters, surfaces)
end
