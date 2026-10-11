defmodule Cauldron2D.GameMaker.Rooms do
  @moduledoc """
  Leaving one room and entering another, in GameMaker's order:

  1. leaving: every instance's room end event; then every instance that is not
     persistent runs its clean-up event and is removed
  2. entering: each instance the room places, in the room's order, is created — its
     pre-create and create events — and runs its own creation code; an instance whose
     id is already present (a persistent one) is not placed again
  3. in the game's first room, every instance's game start event
  4. the room's creation code

  An instance a GameMaker Studio 2 room places on an instance layer takes that layer's
  depth, and is marked as on it (`room_layer`).
  5. every instance's room start event
  """

  alias Cauldron2D.GameMaker.Room
  alias Cauldron2D.GameMaker.Room.Instance, as: Placed
  alias Cauldron2D.GameMaker.World

  @room_start 4
  @room_end 5
  @game_start 2

  @doc "The world in room `room`."
  @spec enter(World.t(), non_neg_integer()) :: World.t()
  def enter(%World{} = world, room) do
    first? = is_nil(world.room)
    %Room{} = definition = Enum.at(world.data.rooms, room)

    world
    |> leave(first?)
    |> Map.merge(%{
      room: room,
      pending_room: nil,
      views: definition.views,
      scroll: %{},
      layers: %{},
      hidden_tiles: MapSet.new(),
      added_tiles: [],
      particles: []
    })
    |> place(definition)
    |> each_instance(first?, :other, @game_start)
    |> World.run_named("gml_Room_#{definition.name}_Create", nil)
    |> each_instance(true, :other, @room_start)
  end

  defp leave(world, true), do: world

  defp leave(world, false) do
    world = each_instance(world, true, :other, @room_end)

    world.order
    |> Enum.reject(&World.fetch(world, &1).persistent)
    |> Enum.reduce(world, fn id, world ->
      world |> World.perform(id, :clean_up, 0) |> World.remove(id)
    end)
  end

  defp place(world, %Room{name: name, instances: instances} = room) do
    depths = layer_depths(room)

    {world, _numbered} =
      Enum.reduce(instances, {world, 0}, fn placed, {world, numbered} ->
        cond do
          World.fetch(world, placed.id) ->
            {world, numbered + if(placed.creation_code, do: 1, else: 0)}

          placed.object < 0 ->
            {world, numbered}

          true ->
            create(world, name, placed, numbered, depths)
        end
      end)

    world
  end

  defp create(world, room_name, %Placed{} = placed, numbered, depths) do
    fields = placed |> fields() |> put_depth(Map.get(depths, placed.id))
    {world, id} = World.create(world, placed.object, placed.position, fields)

    if placed.creation_code,
      do:
        {World.run_named(world, "gml_RoomCC_#{room_name}_#{numbered}_Create", id), numbered + 1},
      else: {world, numbered}
  end

  defp fields(%Placed{} = placed) do
    {scale_x, scale_y} = placed.scale
    {red, green, blue, alpha} = placed.colour
    {speed, index} = placed.image

    %{
      id: placed.id,
      image_xscale: scale_x,
      image_yscale: scale_y,
      image_angle: placed.rotation,
      image_blend: {red, green, blue},
      image_alpha: alpha / 255,
      image_speed: speed,
      image_index: index
    }
  end

  defp layer_depths(%Room{layers: layers}) do
    for %{content: {:instances, ids}, depth: depth} <- layers,
        id <- ids,
        into: %{},
        do: {id, depth}
  end

  defp put_depth(fields, nil), do: fields
  defp put_depth(fields, depth), do: Map.merge(fields, %{depth: depth, room_layer: true})

  defp each_instance(world, false, _type, _subtype), do: world

  defp each_instance(world, true, type, subtype),
    do: Enum.reduce(world.order, world, &World.perform(&2, &1, type, subtype))
end
