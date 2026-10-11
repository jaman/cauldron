defmodule Cauldron2D.GameMaker.Draw do
  @moduledoc """
  A running game's frame as a `Cauldron2D.DrawList`, in room pixels.

      {world, items} = Cauldron2D.GameMaker.Draw.run(world)
      {world, gui} = Cauldron2D.GameMaker.Draw.gui(world)

  `run/1` gives the room's own pictures — GameMaker Studio 1 backgrounds and tiles, or
  GameMaker Studio 2 background, tile and asset layers — every visible instance, and the
  particles (`Cauldron2D.GameMaker.Particles`).
  An instance whose object has code for the draw event runs it, and that code adds
  what it draws with `sprite/4`, `rectangle/4`, `text/5` and `item/2`; any other instance is drawn as its
  sprite at its frame, scale, angle, blend and alpha. Instances of equal depth draw
  newest first, so the one made earliest is in front, as the runtime keeps each new
  instance at the head of its depth's list; and at equal depth, the instances a
  GameMaker Studio 2 room placed on its own layer (`room_layer`) are in front of those
  code made, which the runtime keeps on a layer of its own. `gui/1` runs the draw GUI
  events the same way, for items in window pixels.

  Items name their pictures as `Cauldron2D.GameMaker.Pictures.table/2` keys them:
  `{:sprite, sprite, frame}`, `{:background, background}`,
  `{:tile, background, tile}`, `{:tile, background, {x, y, width, height}}`,
  `{:sprite_part, sprite, {x, y, width, height}}`, `{:glyph, font, character}` and `:pixel`, a single white pixel scaled and blended into a filled rectangle.
  A room layer's tiles are one item, `{:tile_layer, room, layer, blend}`
  (`Cauldron2D.GameMaker.TileLayers`, whose `raster/3` draws it).
  A tile added by code (`World.add_tile/5`) is `{:part, {:sprite, sprite, 0}, {x, y,
  width, height}}`: that part of the picture `{:sprite, sprite, 0}` names
  (`Cauldron2D.GameMaker.Surfaces.lookup/2` cuts it).
  """

  alias Cauldron2D.GameMaker.Background
  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.Particles
  alias Cauldron2D.GameMaker.PartSystems
  alias Cauldron2D.GameMaker.Room
  alias Cauldron2D.GameMaker.Room.Layer
  alias Cauldron2D.GameMaker.Room.Tile
  alias Cauldron2D.GameMaker.Sprite
  alias Cauldron2D.GameMaker.Text
  alias Cauldron2D.GameMaker.TileLayers
  alias Cauldron2D.GameMaker.World

  @draw 0
  @draw_gui 64
  @back 1_000_000_000
  @front -1_000_000_000

  @doc "The world after its draw events, and the frame's draw list."
  @spec run(World.t()) :: {World.t(), [Cauldron2D.DrawList.item()]}
  def run(%World{} = world) do
    room = Enum.at(world.data.rooms, world.room)
    {world, instances} = instances(world, @draw)

    {world,
     room_items(world, room) ++
       added_tile_items(world) ++
       instances ++ Particles.items(world) ++ PartSystems.automatic_items(world)}
  end

  @doc "The world after its draw GUI events, and what they drew."
  @spec gui(World.t()) :: {World.t(), [Cauldron2D.DrawList.item()]}
  def gui(%World{} = world) do
    world.order
    |> Enum.filter(&World.handles?(world, &1, :draw, @draw_gui))
    |> Enum.reduce({world, []}, fn id, {world, items} ->
      {world, drawn} = drawn_by(world, id, @draw_gui)
      {world, items ++ drawn}
    end)
  end

  @doc "The background colour the room clears to, `{r, g, b, a}`."
  @spec background(World.t()) :: {byte(), byte(), byte(), byte()}
  def background(%World{} = world) do
    case Enum.at(world.data.rooms, world.room) do
      %Room{fill: true, colour: {red, green, blue, _alpha}} -> {red, green, blue, 255}
      _ -> {0, 0, 0, 255}
    end
  end

  @doc """
  From draw code: the world with frame `frame` of sprite `sprite` drawn at `{x, y}`, at
  the drawing instance's depth unless `:depth` is given. Other options are those of a
  draw list item: `:scale`, `:angle`, `:blend`, `:alpha`.
  """
  @spec sprite(World.t(), integer(), number(), {number(), number()}, keyword()) :: World.t()
  def sprite(%World{} = world, sprite, frame, position, opts \\ []) do
    case World.sprite(world, sprite) do
      %Sprite{frames: [_ | _] = frames} = definition ->
        item =
          Map.merge(
            %{
              picture: {:sprite, sprite, Integer.mod(floor(frame), length(frames))},
              position: position,
              origin: definition.origin
            },
            Map.new(opts)
          )

        %{world | drawing: [item | world.drawing]}

      _ ->
        world
    end
  end

  @doc """
  From draw code: the world with the rectangle `{left, top, right, bottom}` filled with
  `colour` `{r, g, b}`. Options: `:alpha`, `:depth`.
  """
  @spec rectangle(
          World.t(),
          {number(), number(), number(), number()},
          {byte(), byte(), byte()},
          keyword()
        ) ::
          World.t()
  def rectangle(%World{} = world, {left, top, right, bottom}, colour, opts \\ []) do
    item =
      Map.merge(
        %{
          picture: :pixel,
          position: {left, top},
          scale: {right - left, bottom - top},
          blend: colour
        },
        Map.new(opts)
      )

    %{world | drawing: [item | world.drawing]}
  end

  @doc """
  The draw list item of a line `width` pixels wide from `from` to `to` in `colour`
  `{r, g, b}` (`draw_line_width`): a white pixel stretched along the line and turned
  to it. Options: `:alpha`, `:depth`. Usable on a surface (`Cauldron2D.GameMaker.Surfaces.draw/3`)
  as well as in a frame (`item/2`).
  """
  @spec line_item(
          {number(), number()},
          {number(), number()},
          number(),
          {byte(), byte(), byte()},
          keyword()
        ) ::
          map()
  def line_item({x1, y1}, {x2, y2}, width, colour, opts \\ []) do
    length = max(:math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)), 1)

    Map.merge(
      %{
        picture: :pixel,
        position: {x1, y1},
        origin: {0, 0.5},
        scale: {length, width},
        angle: :math.atan2(-(y2 - y1), x2 - x1) * 180 / :math.pi(),
        blend: colour
      },
      Map.new(opts)
    )
  end

  @doc "From draw code: the world with a line drawn (`line_item/5`)."
  @spec line(
          World.t(),
          {number(), number()},
          {number(), number()},
          number(),
          {byte(), byte(), byte()},
          keyword()
        ) ::
          World.t()
  def line(%World{} = world, from, to, width, colour, opts \\ []),
    do: %{world | drawing: [line_item(from, to, width, colour, opts) | world.drawing]}

  @doc """
  From draw code: the world with `string` drawn in `font` at `{x, y}`, laid out and
  styled by `Cauldron2D.GameMaker.Text.items/5` with `opts`.
  """
  @spec text(World.t(), Text.font(), String.t(), {number(), number()}, keyword()) :: World.t()
  def text(%World{} = world, font, string, position, opts \\ []) do
    items = Text.items(world.data, font, string, position, opts)
    %{world | drawing: Enum.reverse(items, world.drawing)}
  end

  @doc """
  From draw code: the world with `item`, any `Cauldron2D.DrawList` item, drawn — a picture
  the game names itself, as its own picture table keys it. It takes the drawing
  instance's depth unless it has its own.
  """
  @spec item(World.t(), map()) :: World.t()
  def item(%World{} = world, %{picture: _picture, position: _position} = item),
    do: %{world | drawing: [item | world.drawing]}

  @doc """
  From draw code: the world with instance `id` drawn as GameMaker draws an instance with
  no draw event of its own (`draw_self`): its sprite's frame at `image_index`, scaled,
  turned, blended and faded as the instance is.
  """
  @spec self(World.t(), non_neg_integer()) :: World.t()
  def self(%World{} = world, id) do
    case World.fetch(world, id) do
      nil -> world
      instance -> %{world | drawing: Enum.reverse(self_item(world, instance), world.drawing)}
    end
  end

  defp instances(world, subtype) do
    world
    |> drawing_order()
    |> Enum.filter(&World.fetch(world, &1).visible)
    |> Enum.reduce({world, []}, fn id, {world, items} ->
      {world, drawn} =
        if World.handles?(world, id, :draw, subtype),
          do: drawn_by(world, id, subtype),
          else: {world, self_item(world, World.fetch(world, id))}

      {world, items ++ drawn}
    end)
  end

  defp drawing_order(%World{order: order} = world) do
    {placed, made} =
      order |> Enum.reverse() |> Enum.split_with(&World.fetch(world, &1).room_layer)

    made ++ placed
  end

  defp drawn_by(world, id, subtype) do
    depth = World.fetch(world, id).depth
    world = World.perform(%{world | drawing: []}, id, :draw, subtype)
    items = world.drawing |> Enum.reverse() |> Enum.map(&Map.put_new(&1, :depth, depth))
    {%{world | drawing: []}, items}
  end

  defp self_item(world, %Instance{} = instance) do
    case World.sprite(world, instance.sprite_index) do
      %Sprite{frames: [_ | _] = frames} = sprite ->
        [
          %{
            picture:
              {:sprite, instance.sprite_index,
               Integer.mod(floor(instance.image_index), length(frames))},
            position: {instance.x, instance.y},
            origin: sprite.origin,
            scale: {instance.image_xscale, instance.image_yscale},
            angle: instance.image_angle,
            blend: instance.image_blend,
            alpha: instance.image_alpha,
            depth: instance.depth
          }
        ]

      _ ->
        []
    end
  end

  defp room_items(world, %Room{layers: []} = room) do
    backdrops(world, room) ++
      for(
        tile <- room.tiles,
        area?(tile),
        not MapSet.member?(world.hidden_tiles, tile.depth),
        do: tile_item(tile, :tile, tile.depth, {0, 0})
      )
  end

  defp room_items(world, %Room{} = room) do
    world |> World.layers() |> Enum.flat_map(&layer_items(world, room, scrolled(world, &1)))
  end

  defp added_tile_items(%World{added_tiles: tiles, hidden_tiles: hidden}) do
    for %{sprite: sprite, source: source, position: position, depth: depth} <- tiles,
        not MapSet.member?(hidden, depth),
        do: %{picture: {:part, {:sprite, sprite, 0}, source}, position: position, depth: depth}
  end

  defp backdrops(world, %Room{} = room) do
    for backdrop <- room.backdrops,
        backdrop.enabled,
        backdrop.background >= 0,
        %Background{picture: %{bounds: size}} <- [
          Enum.at(world.data.backgrounds, backdrop.background)
        ],
        position <- repeats(backdrop.position, size, backdrop.tiled, room.size) do
      %{
        picture: {:background, backdrop.background},
        position: position,
        depth: if(backdrop.foreground, do: @front, else: @back)
      }
    end
  end

  defp area?(%Tile{source: {_x, _y, width, height}}), do: width > 0 and height > 0

  defp tile_item(%Tile{} = tile, kind, depth, {offset_x, offset_y}) do
    {x, y} = tile.position
    {red, green, blue, alpha} = tile.colour

    %{
      picture: {kind, tile.picture, tile.source},
      position: {x + offset_x, y + offset_y},
      scale: tile.scale,
      blend: {red, green, blue},
      alpha: alpha / 255,
      depth: depth
    }
  end

  defp scrolled(%World{scroll: scroll}, %Layer{id: id, offset: {x, y}} = layer) do
    {dx, dy} = Map.get(scroll, id, {0, 0})
    %{layer | offset: {x + dx, y + dy}}
  end

  defp layer_items(_world, _room, %Layer{visible: false}), do: []

  defp layer_items(world, room, %Layer{content: {:background, background}} = layer),
    do: background_layer(world, room, layer, background)

  defp layer_items(world, _room, %Layer{content: {:assets, assets}} = layer) do
    blend = world.layers |> Map.get(layer.name, %{}) |> Map.get(:tile_blend)

    List.wrap(TileLayers.item(world.data, world.room, layer, blend)) ++
      Enum.map(assets.sprites, &placed_sprite(&1, layer))
  end

  defp layer_items(world, _room, %Layer{content: {:tiles, _tiles}} = layer),
    do: List.wrap(TileLayers.item(world.data, world.room, layer, nil))

  defp layer_items(_world, _room, %Layer{}), do: []

  defp background_layer(_world, %Room{size: {width, height}}, layer, %{
         visible: true,
         sprite: -1,
         colour: {r, g, b, a}
       }) do
    [
      %{
        picture: :pixel,
        position: layer.offset,
        scale: {width, height},
        blend: {r, g, b},
        alpha: a / 255,
        depth: layer.depth
      }
    ]
  end

  defp background_layer(world, %Room{} = room, layer, %{visible: true} = background) do
    case World.sprite(world, background.sprite) do
      %Sprite{frames: [_ | _], size: size} ->
        {red, green, blue, alpha} = background.colour
        {width, height} = room.size
        {sprite_width, sprite_height} = size

        {xscale, yscale} = {Map.get(background, :xscale, 1), Map.get(background, :yscale, 1)}

        scale =
          if background.stretch,
            do: {width / sprite_width, height / sprite_height},
            else: {xscale, yscale}

        {scaled_width, scaled_height} =
          {sprite_width * elem(scale, 0), sprite_height * elem(scale, 1)}

        for position <-
              repeats(layer.offset, {scaled_width, scaled_height}, background.tiled, room.size) do
          %{
            picture: {:sprite, background.sprite, 0},
            position: position,
            scale: scale,
            blend: {red, green, blue},
            alpha: alpha / 255,
            depth: if(background.foreground, do: @front, else: layer.depth)
          }
        end

      _ ->
        []
    end
  end

  defp background_layer(_world, _room, _layer, _background), do: []

  defp placed_sprite(sprite, %Layer{offset: {offset_x, offset_y}, depth: depth}) do
    {x, y} = sprite.position
    {red, green, blue, alpha} = sprite.colour

    %{
      picture: {:sprite, sprite.sprite, max(floor(sprite.frame), 0)},
      position: {x + offset_x, y + offset_y},
      scale: sprite.scale,
      angle: sprite.rotation,
      blend: {red, green, blue},
      alpha: alpha / 255,
      depth: depth
    }
  end

  defp repeats({x, y}, {width, height}, {across, down}, {room_width, room_height}) do
    for column <- spans(x, width, across, room_width),
        row <- spans(y, height, down, room_height),
        do: {column, row}
  end

  defp spans(start, _size, false, _room), do: [start]

  defp spans(start, size, true, room) when size > 0 do
    first = start - size * Float.ceil(start / size)
    Enum.take_while(Stream.iterate(first, &(&1 + size)), &(&1 < room))
  end
end
