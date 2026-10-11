defmodule Cauldron2D.GameMaker.Step do
  @moduledoc """
  One step of a running game, in GameMaker's order:

  1. every instance's `xprevious` and `yprevious` become its position
  2. begin step events
  3. alarms: each alarm above zero counts down, and one reaching zero turns off and runs
     its alarm event
  4. keyboard events: a held key's keyboard event, a pressed key's key press event, a
     released key's key release event, each also as "any key" (`1`) when there is one,
     and the keyboard event "no key" (`0`) when nothing is held; then mouse events
  5. step events
  6. built-in motion: friction slows `speed` towards zero, gravity adds to `hspeed` and
     `vspeed`, then the position moves by them; an instance that is now wholly outside
     the room, and was not before, runs the outside room event
  7. collision events (`Cauldron2D.GameMaker.Collide`)
  8. end step events, then views that follow an object move, then every room layer with
     a speed scrolls by it (`World`'s `scroll`)
    (`Cauldron2D.GameMaker.Views`)
  9. animation: `image_index` advances by `image_speed` times the sprite's own speed,
     wrapping at the sprite's frame count, and an instance that wrapped runs the
     animation end event
  10. a room change asked for during the step happens

  Within each stage instances act in creation order; an instance destroyed partway
  through a stage takes no further part in it.

  `input` has the GameMaker key codes `held`, `pressed` this step and `released` this
  step, and may have `:mouse`: `%{position: {x, y}, held: buttons, pressed: buttons,
  released: buttons}`, buttons being sets of `:left`, `:right` and `:middle`, position
  in room pixels.
  """

  alias Cauldron2D.GameMaker.Collide
  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.Particles
  alias Cauldron2D.GameMaker.PartSystems
  alias Cauldron2D.GameMaker.Rooms
  alias Cauldron2D.GameMaker.Sprite
  alias Cauldron2D.GameMaker.Views
  alias Cauldron2D.GameMaker.World
  alias Cauldron2D.Overlap
  alias Cauldron2D.Shape

  @begin_step 1
  @end_step 2
  @no_key 0
  @any_key 1
  @outside_room 0
  @animation_end 7

  @local_mouse %{left: {0, 4, 7}, right: {1, 5, 8}, middle: {2, 6, 9}}
  @global_mouse %{left: {50, 53, 56}, right: {51, 54, 57}, middle: {52, 55, 58}}
  @no_button 3
  @mouse_enter 10
  @mouse_leave 11

  @doc "The world one step on, with `input` as the players' input this step."
  @spec run(World.t(), World.input()) :: World.t()
  def run(%World{} = world, input) do
    %{world | input: input, steps: world.steps + 1}
    |> each(&%{&1 | xprevious: &1.x, yprevious: &1.y})
    |> every(:step, @begin_step)
    |> alarms()
    |> keyboard(input)
    |> mouse(Map.get(input, :mouse))
    |> every(:step, 0)
    |> motion()
    |> Collide.events()
    |> every(:step, @end_step)
    |> Views.follow()
    |> scroll()
    |> animate()
    |> Particles.step()
    |> PartSystems.step()
    |> change_room()
  end

  defp each(world, fun) do
    %{world | instances: Map.new(world.instances, fn {id, instance} -> {id, fun.(instance)} end)}
  end

  defp every(world, type, subtype),
    do: Enum.reduce(world.order, world, &World.perform(&2, &1, type, subtype))

  defp alarms(world) do
    Enum.reduce(world.order, world, fn id, world ->
      Enum.reduce(0..11, world, &count_down(&2, id, &1))
    end)
  end

  defp count_down(world, id, number) do
    case World.fetch(world, id) do
      %Instance{} = instance ->
        case Instance.alarm(instance, number) do
          1 ->
            world
            |> World.update(id, &Instance.put_alarm(&1, number, -1))
            |> World.perform(id, :alarm, number)

          steps when steps > 1 ->
            World.update(world, id, &Instance.put_alarm(&1, number, steps - 1))

          _off ->
            world
        end

      nil ->
        world
    end
  end

  defp keyboard(world, input) do
    world
    |> keys(:keyboard, input.held)
    |> keys(:key_press, input.pressed)
    |> keys(:key_release, input.released)
    |> then(fn world ->
      if MapSet.size(input.held) == 0, do: every(world, :keyboard, @no_key), else: world
    end)
  end

  defp keys(world, type, codes) do
    world = Enum.reduce(Enum.sort(codes), world, &every(&2, type, &1))
    if MapSet.size(codes) > 0, do: every(world, type, @any_key), else: world
  end

  defp mouse(world, nil), do: world

  defp mouse(world, mouse) do
    over = for id <- world.order, under?(world, id, mouse.position), into: MapSet.new(), do: id

    world
    |> global_buttons(mouse)
    |> local_buttons(mouse, over)
    |> hover(over)
  end

  defp global_buttons(world, mouse) do
    Enum.reduce(@global_mouse, world, fn {button, {held, pressed, released}}, world ->
      world
      |> when_button(button in mouse.held, &every(&1, :mouse, held))
      |> when_button(button in mouse.pressed, &every(&1, :mouse, pressed))
      |> when_button(button in mouse.released, &every(&1, :mouse, released))
    end)
  end

  defp local_buttons(world, mouse, over) do
    ids = Enum.filter(world.order, &(&1 in over))

    Enum.reduce(ids, world, fn id, world ->
      world =
        Enum.reduce(@local_mouse, world, fn {button, {held, pressed, released}}, world ->
          world
          |> when_button(button in mouse.held, &World.perform(&1, id, :mouse, held))
          |> when_button(button in mouse.pressed, &World.perform(&1, id, :mouse, pressed))
          |> when_button(button in mouse.released, &World.perform(&1, id, :mouse, released))
        end)

      when_button(world, MapSet.size(mouse.held) == 0, &World.perform(&1, id, :mouse, @no_button))
    end)
  end

  defp hover(world, over) do
    entered = Enum.filter(world.order, &(&1 in over and &1 not in world.hovered))
    left = Enum.filter(world.order, &(&1 not in over and &1 in world.hovered))

    world = Enum.reduce(entered, world, &World.perform(&2, &1, :mouse, @mouse_enter))
    world = Enum.reduce(left, world, &World.perform(&2, &1, :mouse, @mouse_leave))
    %{world | hovered: over}
  end

  defp when_button(world, true, fun), do: fun.(world)
  defp when_button(world, false, _fun), do: world

  defp under?(world, id, point) do
    instance = World.fetch(world, id)

    case Collide.shape(world, instance, {instance.x, instance.y}) do
      nil -> false
      shape -> Overlap.point?(shape, point)
    end
  end

  defp motion(world) do
    Enum.reduce(world.order, world, fn id, world ->
      world
      |> World.update(id, &move/1)
      |> outside(id)
    end)
  end

  defp move(%Instance{} = instance) do
    instance
    |> slow()
    |> fall()
    |> then(&%{&1 | x: &1.x + &1.hspeed, y: &1.y + &1.vspeed})
  end

  defp slow(%Instance{friction: friction, speed: speed} = instance)
       when friction != 0 and speed != 0 do
    slowed = if speed > 0, do: max(speed - friction, 0.0), else: min(speed + friction, 0.0)
    Instance.put_motion(instance, %{speed: slowed})
  end

  defp slow(instance), do: instance

  defp fall(%Instance{gravity: gravity} = instance) when gravity != 0 do
    {cos, sin} = Cauldron2D.Turn.cos_sin(instance.gravity_direction)

    Instance.put_motion(instance, %{
      hspeed: instance.hspeed + gravity * cos,
      vspeed: instance.vspeed - gravity * sin
    })
  end

  defp fall(instance), do: instance

  defp outside(world, id) do
    with %Instance{} = instance <- World.fetch(world, id),
         %Shape{} = shape <- Collide.shape(world, instance, {instance.x, instance.y}) do
      was_outside = MapSet.member?(world.outside, id)
      now_outside = outside_room?(world, shape)
      world = %{world | outside: mark_outside(world.outside, id, now_outside)}

      if now_outside and not was_outside,
        do: World.perform(world, id, :other, @outside_room),
        else: world
    else
      _ -> world
    end
  end

  defp mark_outside(outside, id, true), do: MapSet.put(outside, id)
  defp mark_outside(outside, id, false), do: MapSet.delete(outside, id)

  defp outside_room?(world, shape) do
    {width, height} = Enum.at(world.data.rooms, world.room).size
    {left, top, right, bottom} = Shape.bounds(shape)
    right <= 0 or bottom <= 0 or left >= width or top >= height
  end

  defp scroll(%World{} = world) do
    layers = World.layers(world)

    scroll =
      for %{speed: {sx, sy}, id: id} <- layers, sx != 0 or sy != 0, reduce: world.scroll do
        scroll -> Map.update(scroll, id, {sx, sy}, fn {x, y} -> {x + sx, y + sy} end)
      end

    %{world | scroll: scroll}
  end

  defp animate(world) do
    Enum.reduce(world.order, world, fn id, world ->
      case World.fetch(world, id) do
        nil -> world
        instance -> animate(world, instance, World.sprite(world, instance.sprite_index))
      end
    end)
  end

  defp animate(world, _instance, nil), do: world
  defp animate(world, _instance, %Sprite{frames: []}), do: world

  defp animate(world, %Instance{} = instance, %Sprite{} = sprite) do
    count = length(sprite.frames)
    index = instance.image_index + instance.image_speed * rate(world, sprite)
    wrapped = index >= count or index < 0
    world = World.update(world, instance.id, &%{&1 | image_index: wrap(index, count)})

    if wrapped, do: World.perform(world, instance.id, :other, @animation_end), else: world
  end

  defp rate(_world, %Sprite{speed: {rate, :per_frame}}), do: rate

  defp rate(world, %Sprite{speed: {rate, :per_second}}),
    do: rate / (world.data.general.fps || Enum.at(world.data.rooms, world.room).speed)

  defp wrap(index, count), do: index - count * Float.floor(index / count)

  defp change_room(%World{pending_room: nil} = world), do: world
  defp change_room(%World{pending_room: room} = world), do: Rooms.enter(world, room)
end
