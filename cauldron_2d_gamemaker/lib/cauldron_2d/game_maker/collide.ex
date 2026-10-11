defmodule Cauldron2D.GameMaker.Collide do
  @moduledoc """
  Collisions between instances, as GameMaker decides them.

  An instance collides with the mask of its `mask_index` sprite, or of its
  `sprite_index` sprite when it has no mask sprite, at the frame `image_index` shows,
  placed at its position with its scale and angle. A sprite without masks collides as
  its collision box. An instance with neither sprite collides with nothing.

  `events/1` runs the step's collision events: for every instance, in creation order,
  and every object it has a collision event for, each other instance of that object
  (or of an object descending from it) that overlaps it runs the event with that
  instance as `other`. When the other instance is solid, the instance is first put back
  where it was at the start of the step; after the event it moves by its speed again
  and goes back once more if it still overlaps.
  """

  alias Cauldron2D.GameMaker.Instance
  alias Cauldron2D.GameMaker.Sprite
  alias Cauldron2D.GameMaker.World
  alias Cauldron2D.Overlap
  alias Cauldron2D.Shape

  @type target :: non_neg_integer() | :all | {:id, non_neg_integer()}

  @doc "The shape instance `instance` collides with at `{x, y}`, `nil` for none."
  @spec shape(World.t(), Instance.t(), {number(), number()}) :: Shape.t() | nil
  def shape(%World{} = world, %Instance{} = instance, position) do
    sprite_index =
      if instance.mask_index >= 0, do: instance.mask_index, else: instance.sprite_index

    case World.sprite(world, sprite_index) do
      nil -> nil
      sprite -> placed(sprite, instance, position)
    end
  end

  @doc "Whether instance `id`, moved to `{x, y}`, overlaps an instance of `object` (`:all` for any)."
  @spec meeting?(World.t(), non_neg_integer(), {number(), number()}, non_neg_integer() | :all) ::
          boolean()
  def meeting?(%World{} = world, id, position, object),
    do: place(world, id, position, object) != nil

  @doc "The first instance of `object` that instance `id`, moved to `{x, y}`, overlaps; `nil` for none."
  @spec place(World.t(), non_neg_integer(), {number(), number()}, non_neg_integer() | :all) ::
          non_neg_integer() | nil
  def place(%World{} = world, id, position, object) do
    with %Instance{} = instance <- World.fetch(world, id),
         %Shape{} = mine <- shape(world, instance, position) do
      world
      |> World.instances_of(object)
      |> Enum.find(fn other -> other != id and touches?(world, mine, other) end)
    else
      _ -> nil
    end
  end

  @doc """
  The first instance of `target` whose shape holds the point `{x, y}`
  (`collision_point`, `instance_position`, `position_meeting`); `nil` for none. `target`
  is an object index (its descendants count), `:all`, or `{:id, id}` for one instance.
  """
  @spec at_point(World.t(), {number(), number()}, target()) :: non_neg_integer() | nil
  def at_point(%World{} = world, point, target) do
    world
    |> candidates(target)
    |> Enum.find(&holds?(world, &1, point))
  end

  @doc """
  The first instance of `target` the segment from `from` to `to` passes through
  (`collision_line`); `nil` for none. `target` as for `at_point/3`.
  """
  @spec on_line(World.t(), {number(), number()}, {number(), number()}, target()) ::
          non_neg_integer() | nil
  def on_line(%World{} = world, from, to, target) do
    world
    |> candidates(target)
    |> Enum.find(fn id ->
      with %Instance{} = instance <- World.fetch(world, id),
           %Shape{} = shape <- shape(world, instance, {instance.x, instance.y}) do
        Overlap.line?(shape, from, to)
      else
        _ -> false
      end
    end)
  end

  @doc "Whether instance `id`, moved to `{x, y}`, overlaps no solid instance."
  @spec free?(World.t(), non_neg_integer(), {number(), number()}) :: boolean()
  def free?(%World{} = world, id, position) do
    with %Instance{} = instance <- World.fetch(world, id),
         %Shape{} = mine <- shape(world, instance, position) do
      not Enum.any?(world.order, fn other ->
        other != id and World.fetch(world, other).solid and touches?(world, mine, other)
      end)
    else
      _ -> true
    end
  end

  @doc """
  The world with instance `id` bounced as GameMaker's `move_bounce_solid(advanced)`
  (`against` `:solid`) or `move_bounce_all(advanced)` (`:all`) bounces it. Overlapping
  something it bounces against, it first goes back to `xprevious`, `yprevious`. Simple
  bouncing reverses `hspeed` where a move across is blocked and `vspeed` where a move
  down is blocked, both when both are blocked or when only the move along both is
  blocked. Advanced bouncing turns from its direction, rounded to 10°, both ways in
  steps of 10° until a move of its speed is clear, and when anything was blocked takes
  direction `180 + left + right − direction`.
  """
  @spec bounce(World.t(), non_neg_integer(), boolean(), :solid | :all) :: World.t()
  def bounce(%World{} = world, id, advanced, against) do
    %Instance{x: x, y: y} = instance = World.fetch(world, id)
    blocked = not clear?(world, id, {x, y}, against)

    world =
      if blocked,
        do: World.update(world, id, &%{&1 | x: instance.xprevious, y: instance.yprevious}),
        else: world

    if advanced,
      do: bounce_advanced(world, id, against, blocked),
      else: bounce_simple(world, id, against)
  end

  defp bounce_simple(world, id, against) do
    %Instance{x: x, y: y, hspeed: hspeed, vspeed: vspeed} = World.fetch(world, id)
    across = clear?(world, id, {x + hspeed, y}, against)
    down = clear?(world, id, {x, y + vspeed}, against)
    both = clear?(world, id, {x + hspeed, y + vspeed}, against)

    {hspeed, vspeed} =
      cond do
        not across and not down -> {-hspeed, -vspeed}
        across and down and not both -> {-hspeed, -vspeed}
        not across -> {-hspeed, vspeed}
        not down -> {hspeed, -vspeed}
        true -> {hspeed, vspeed}
      end

    World.update(world, id, &Instance.put_motion(&1, %{hspeed: hspeed, vspeed: vspeed}))
  end

  defp bounce_advanced(world, id, against, blocked) do
    %Instance{x: x, y: y, speed: speed, direction: direction} = World.fetch(world, id)
    rounded = 10.0 * Float.round(direction / 10.0)
    {left, left_blocked} = turn_until_clear(world, id, {x, y}, speed, rounded, -10, against)
    {right, right_blocked} = turn_until_clear(world, id, {x, y}, speed, rounded, 10, against)

    if blocked or left_blocked or right_blocked,
      do:
        World.update(
          world,
          id,
          &Instance.put_motion(&1, %{direction: 180 + left + right - rounded})
        ),
      else: world
  end

  defp turn_until_clear(world, id, {x, y}, speed, from, by, against) do
    Enum.reduce_while(1..35, {from, false}, fn _turn, {direction, blocked} ->
      direction = direction + by
      radians = direction * :math.pi() / 180
      position = {x + speed * :math.cos(radians), y - speed * :math.sin(radians)}

      if clear?(world, id, position, against),
        do: {:halt, {direction, blocked}},
        else: {:cont, {direction, true}}
    end)
  end

  defp clear?(world, id, position, :solid), do: free?(world, id, position)
  defp clear?(world, id, position, :all), do: not meeting?(world, id, position, :all)

  @doc "The world after the step's collision events."
  @spec events(World.t()) :: World.t()
  def events(%World{} = world) do
    Enum.reduce(world.order, world, fn id, world ->
      case World.fetch(world, id) do
        nil -> world
        instance -> Enum.reduce(targets(world, instance), world, &collide_with(&2, id, &1))
      end
    end)
  end

  defp targets(world, %Instance{object: object}) do
    for {{:collision, target}, _owner} <- elem(world.owners, object), do: target
  end

  defp collide_with(world, id, target) do
    world
    |> World.instances_of(target)
    |> Enum.reduce(world, fn other, world ->
      with %Instance{} = instance <- World.fetch(world, id),
           %Instance{} = them <- World.fetch(world, other),
           true <- other != id,
           %Shape{} = mine <- shape(world, instance, {instance.x, instance.y}),
           true <- touches?(world, mine, other) do
        collide(world, id, target, them)
      else
        _ -> world
      end
    end)
  end

  defp collide(world, id, target, %Instance{solid: false, id: other}),
    do: World.perform(world, id, :collision, target, other)

  defp collide(world, id, target, %Instance{solid: true, id: other}) do
    world
    |> World.update(id, &%{&1 | x: &1.xprevious, y: &1.yprevious})
    |> World.perform(id, :collision, target, other)
    |> World.update(id, &%{&1 | x: &1.x + &1.hspeed, y: &1.y + &1.vspeed})
    |> back_if_touching(id, other)
  end

  defp back_if_touching(world, id, other) do
    with %Instance{} = instance <- World.fetch(world, id),
         %Shape{} = mine <- shape(world, instance, {instance.x, instance.y}),
         true <- touches?(world, mine, other) do
      World.update(world, id, &%{&1 | x: &1.xprevious, y: &1.yprevious})
    else
      _ -> world
    end
  end

  defp candidates(world, {:id, id}), do: if(World.fetch(world, id), do: [id], else: [])
  defp candidates(world, target), do: World.instances_of(world, target)

  defp holds?(world, id, point) do
    with %Instance{} = instance <- World.fetch(world, id),
         %Shape{} = shape <- shape(world, instance, {instance.x, instance.y}) do
      Overlap.point?(shape, point)
    else
      _ -> false
    end
  end

  defp touches?(world, %Shape{} = mine, other) do
    with %Instance{} = them <- World.fetch(world, other),
         %Shape{} = theirs <- shape(world, them, {them.x, them.y}) do
      Overlap.shapes?(mine, theirs)
    else
      _ -> false
    end
  end

  defp placed(%Sprite{} = sprite, %Instance{} = instance, position) do
    options = [
      scale: {instance.image_xscale, instance.image_yscale},
      angle: instance.image_angle
    ]

    case Sprite.mask(sprite, floor(instance.image_index)) do
      nil ->
        {left, top, right, bottom} = sprite.box
        {origin_x, origin_y} = sprite.origin

        Shape.new(
          {:rectangle, right - left + 1, bottom - top + 1},
          position,
          [origin: {origin_x - left, origin_y - top}] ++ options
        )

      mask ->
        Shape.new({:mask, mask}, position, [origin: sprite.origin] ++ options)
    end
  end
end
