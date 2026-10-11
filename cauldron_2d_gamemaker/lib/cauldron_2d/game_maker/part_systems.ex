defmodule Cauldron2D.GameMaker.PartSystems do
  @moduledoc """
  GameMaker's particle systems as its runtime runs them: systems that hold particles,
  particle types that say how each particle starts, moves, changes and draws, and
  emitters that set particles loose over a region. The functions are the game code's
  `part_system_*`, `part_type_*`, `part_emitter_*` and `part_particles_create`, each
  taking and giving the world; random draws come from the world's generator
  (`Cauldron2D.GameMaker.Random`), in the runtime's order.

      {world, system} = PartSystems.system_create(world)
      {world, dust} = PartSystems.type_create(world)
      world = PartSystems.type_sprite(world, dust, sprite, true, false, false)
      {world, emitter} = PartSystems.emitter_create(world, system)
      world =
        world
        |> PartSystems.emitter_region(system, emitter, {x - 4, x + 4, y, y}, :rectangle, :linear)
        |> PartSystems.emitter_burst(system, emitter, dust, 1)

  A particle starts with a speed, direction, angle, size and life drawn from its type's
  ranges, its type's first colour and alpha, and, for a type with a random start frame,
  a frame drawn from 0–9999. `system_update/2` then, for every particle:

    1. ages it a step; one whose life is up dies, setting loose its type's death
       particles where it was, and every living one sets loose its step particles
    2. adds the type's speed increment (never below 0), direction increment and angle
       increment, turns its motion by the type's gravity, and moves it by its speed and
       direction, each shaken by its wiggle
    3. adds the size increment (never below 0), sets its colour, and fades its alpha
       along the type's three alphas, the second at half its life

  and then lets every emitter with a stream burst. A wiggle is a triangle wave from −1
  to 1 times the type's wiggle amount, whose phase is the particle's age plus a
  multiple of a number from 0–99999 drawn when it was made.

  `items/2` gives a system's particles as draw list items in its draw order; a system
  drawn automatically is drawn by `Cauldron2D.GameMaker.Draw` at its depth, and one
  updated automatically is updated with each step.
  """

  alias Cauldron2D.GameMaker.Colour
  alias Cauldron2D.GameMaker.Random
  alias Cauldron2D.GameMaker.World

  @type shape :: :rectangle | :ellipse | :diamond | :line
  @type distribution :: :linear | :gaussian | :invgaussian

  @type_defaults %{
    sprite: -1,
    animate: false,
    stretch: false,
    random_frame: false,
    size: {1.0, 1.0, 0.0, 0.0},
    scale: {1.0, 1.0},
    life: {100, 100},
    step: {nil, 0},
    death: {nil, 0},
    speed: {0.0, 0.0, 0.0, 0.0},
    direction: {0.0, 0.0, 0.0, 0.0},
    gravity: {0.0, 270.0},
    orientation: {0.0, 0.0, 0.0, 0.0, false},
    colour: {:one, {255, 255, 255}},
    alpha: {1.0, 1.0, 1.0},
    additive: false
  }

  @system_defaults %{
    particles: [],
    emitters: %{},
    next_emitter: 0,
    depth: 0,
    automatic_update: true,
    automatic_draw: true,
    old_to_new: true,
    position: {0.0, 0.0}
  }

  @doc "A new particle system; `{world, system}` (`part_system_create`)."
  @spec system_create(World.t()) :: {World.t(), non_neg_integer()}
  def system_create(%World{part_systems: part} = world) do
    id = part.next_system

    part = %{
      part
      | systems: Map.put(part.systems, id, @system_defaults),
        next_system: id + 1
    }

    {%{world | part_systems: part}, id}
  end

  @doc "The world without system `system` and its particles (`part_system_destroy`)."
  @spec system_destroy(World.t(), non_neg_integer()) :: World.t()
  def system_destroy(%World{part_systems: part} = world, system),
    do: %{world | part_systems: %{part | systems: Map.delete(part.systems, system)}}

  @doc "Whether system `system` exists (`part_system_exists`)."
  @spec system_exists?(World.t(), non_neg_integer()) :: boolean()
  def system_exists?(%World{part_systems: part}, system), do: Map.has_key?(part.systems, system)

  @doc "System `system` drawn at `depth` (`part_system_depth`)."
  @spec system_depth(World.t(), non_neg_integer(), number()) :: World.t()
  def system_depth(world, system, depth), do: put_system(world, system, :depth, depth)

  @doc "System `system` updated by itself each step, or only by `system_update/2` (`part_system_automatic_update`)."
  @spec system_automatic_update(World.t(), non_neg_integer(), boolean()) :: World.t()
  def system_automatic_update(world, system, on),
    do: put_system(world, system, :automatic_update, on)

  @doc "System `system` drawn by itself, or only through `items/2` (`part_system_automatic_draw`)."
  @spec system_automatic_draw(World.t(), non_neg_integer(), boolean()) :: World.t()
  def system_automatic_draw(world, system, on), do: put_system(world, system, :automatic_draw, on)

  @doc "A new particle type with GameMaker's defaults; `{world, type}` (`part_type_create`)."
  @spec type_create(World.t()) :: {World.t(), non_neg_integer()}
  def type_create(%World{part_systems: part} = world) do
    id = part.next_type
    part = %{part | types: Map.put(part.types, id, @type_defaults), next_type: id + 1}
    {%{world | part_systems: part}, id}
  end

  @doc "The world without particle type `type` (`part_type_destroy`)."
  @spec type_destroy(World.t(), non_neg_integer()) :: World.t()
  def type_destroy(%World{part_systems: part} = world, type),
    do: %{world | part_systems: %{part | types: Map.delete(part.types, type)}}

  @doc """
  Type `type` drawn as sprite `sprite`: animated through its frames, stretched so its
  frames span the particle's life, starting on a random frame (`part_type_sprite`).
  """
  @spec type_sprite(World.t(), non_neg_integer(), integer(), boolean(), boolean(), boolean()) ::
          World.t()
  def type_sprite(world, type, sprite, animate, stretch, random_frame) do
    update_type(world, type, fn settings ->
      %{
        settings
        | sprite: sprite,
          animate: animate,
          stretch: stretch,
          random_frame: random_frame
      }
    end)
  end

  @doc "Type `type`'s size range, increment a step and wiggle (`part_type_size`)."
  @spec type_size(World.t(), non_neg_integer(), number(), number(), number(), number()) ::
          World.t()
  def type_size(world, type, low, high, increment, wiggle),
    do: put_type(world, type, :size, {low, high, increment, wiggle})

  @doc "Type `type`'s scale `{x, y}` (`part_type_scale`)."
  @spec type_scale(World.t(), non_neg_integer(), number(), number()) :: World.t()
  def type_scale(world, type, x, y), do: put_type(world, type, :scale, {x, y})

  @doc "Type `type`'s life, from `low` to `high` steps (`part_type_life`)."
  @spec type_life(World.t(), non_neg_integer(), number(), number()) :: World.t()
  def type_life(world, type, low, high), do: put_type(world, type, :life, {low, high})

  @doc "Type `type`'s speed range, increment a step and wiggle (`part_type_speed`)."
  @spec type_speed(World.t(), non_neg_integer(), number(), number(), number(), number()) ::
          World.t()
  def type_speed(world, type, low, high, increment, wiggle),
    do: put_type(world, type, :speed, {low, high, increment, wiggle})

  @doc "Type `type`'s direction range, increment a step and wiggle, in degrees (`part_type_direction`)."
  @spec type_direction(World.t(), non_neg_integer(), number(), number(), number(), number()) ::
          World.t()
  def type_direction(world, type, low, high, increment, wiggle),
    do: put_type(world, type, :direction, {low, high, increment, wiggle})

  @doc "Type `type`'s gravity: `amount` a step towards `direction` (`part_type_gravity`)."
  @spec type_gravity(World.t(), non_neg_integer(), number(), number()) :: World.t()
  def type_gravity(world, type, amount, direction),
    do: put_type(world, type, :gravity, {amount, direction})

  @doc """
  Type `type`'s angle range, increment a step and wiggle, and whether the angle is
  added to the direction of motion (`part_type_orientation`).
  """
  @spec type_orientation(
          World.t(),
          non_neg_integer(),
          number(),
          number(),
          number(),
          number(),
          boolean()
        ) :: World.t()
  def type_orientation(world, type, low, high, increment, wiggle, relative),
    do: put_type(world, type, :orientation, {low, high, increment, wiggle, relative})

  @doc """
  Type `type` coloured from hue, saturation and value each drawn from its range when a
  particle is made, 0–255 (`part_type_colour_hsv`).
  """
  @spec type_colour_hsv(
          World.t(),
          non_neg_integer(),
          {number(), number()},
          {number(), number()},
          {number(), number()}
        ) :: World.t()
  def type_colour_hsv(world, type, hue, saturation, value),
    do: put_type(world, type, :colour, {:hsv, hue, saturation, value})

  @doc "Type `type` coloured `colour` `{r, g, b}` (`part_type_colour1`)."
  @spec type_colour1(World.t(), non_neg_integer(), {byte(), byte(), byte()}) :: World.t()
  def type_colour1(world, type, colour), do: put_type(world, type, :colour, {:one, colour})

  @doc "Type `type`'s alpha, the same all its life (`part_type_alpha1`)."
  @spec type_alpha1(World.t(), non_neg_integer(), number()) :: World.t()
  def type_alpha1(world, type, alpha), do: put_type(world, type, :alpha, {alpha, alpha, alpha})

  @doc "Type `type`'s alpha at its start, half its life and its end (`part_type_alpha3`)."
  @spec type_alpha3(World.t(), non_neg_integer(), number(), number(), number()) :: World.t()
  def type_alpha3(world, type, start, middle, finish),
    do: put_type(world, type, :alpha, {start, middle, finish})

  @doc "Type `type` drawn added to what is under it, or over it (`part_type_blend`)."
  @spec type_blend(World.t(), non_neg_integer(), boolean()) :: World.t()
  def type_blend(world, type, additive), do: put_type(world, type, :additive, additive)

  @doc "`number` particles of type `death` set loose where a particle of `type` dies (`part_type_death`)."
  @spec type_death(World.t(), non_neg_integer(), integer(), non_neg_integer()) :: World.t()
  def type_death(world, type, number, death), do: put_type(world, type, :death, {death, number})

  @doc "`number` particles of type `step` set loose each step from each particle of `type` (`part_type_step`)."
  @spec type_step(World.t(), non_neg_integer(), integer(), non_neg_integer()) :: World.t()
  def type_step(world, type, number, step), do: put_type(world, type, :step, {step, number})

  @doc "A new emitter of system `system`; `{world, emitter}` (`part_emitter_create`)."
  @spec emitter_create(World.t(), non_neg_integer()) :: {World.t(), non_neg_integer()}
  def emitter_create(%World{} = world, system) do
    settings = fetch_system(world, system)
    id = settings.next_emitter

    emitter = %{
      region: {0.0, 0.0, 0.0, 0.0},
      shape: :rectangle,
      distribution: :linear,
      stream: {nil, 0}
    }

    world =
      put_system_settings(world, system, %{
        settings
        | emitters: Map.put(settings.emitters, id, emitter),
          next_emitter: id + 1
      })

    {world, id}
  end

  @doc "The world without emitter `emitter` of system `system` (`part_emitter_destroy`)."
  @spec emitter_destroy(World.t(), non_neg_integer(), non_neg_integer()) :: World.t()
  def emitter_destroy(world, system, emitter) do
    settings = fetch_system(world, system)

    put_system_settings(world, system, %{
      settings
      | emitters: Map.delete(settings.emitters, emitter)
    })
  end

  @doc """
  Emitter `emitter`'s region `{xmin, xmax, ymin, ymax}`, its shape and how particles
  spread over it (`part_emitter_region`).
  """
  @spec emitter_region(
          World.t(),
          non_neg_integer(),
          non_neg_integer(),
          {number(), number(), number(), number()},
          shape(),
          distribution()
        ) :: World.t()
  def emitter_region(world, system, emitter, region, shape, distribution) do
    update_emitter(world, system, emitter, fn settings ->
      %{settings | region: region, shape: shape, distribution: distribution}
    end)
  end

  @doc """
  `number` particles of type `type` set loose over emitter `emitter`'s region; a
  negative `number` sets one loose by a 1 in `|number|` chance (`part_emitter_burst`).
  """
  @spec emitter_burst(
          World.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          integer()
        ) ::
          World.t()
  def emitter_burst(world, system, emitter, type, number) when number < 0 do
    {out, random} = Random.next(world.random)
    world = %{world | random: random}
    if rem(out, -number) == 0, do: emitter_burst(world, system, emitter, type, 1), else: world
  end

  def emitter_burst(world, system, emitter, type, number) do
    settings = fetch_system(world, system).emitters |> Map.fetch!(emitter)

    Enum.reduce(1..number//1, world, fn _particle, world ->
      {{x, y}, world} = place(world, settings)
      particles_create(world, system, {x, y}, type, 1)
    end)
  end

  @doc "`number` particles of type `type` set loose at `{x, y}` (`part_particles_create`)."
  @spec particles_create(
          World.t(),
          non_neg_integer(),
          {number(), number()},
          non_neg_integer(),
          integer()
        ) ::
          World.t()
  def particles_create(world, system, position, type, number) do
    case Map.fetch(world.part_systems.types, type) do
      {:ok, settings} when number > 0 ->
        Enum.reduce(1..number, world, fn _particle, world ->
          {particle, world} = particle(world, type, settings, position)
          update_system(world, system, &%{&1 | particles: &1.particles ++ [particle]})
        end)

      _none ->
        world
    end
  end

  @doc "The world with system `system` one step on (`part_system_update`)."
  @spec system_update(World.t(), non_neg_integer()) :: World.t()
  def system_update(world, system) do
    if system_exists?(world, system) do
      world
      |> age(system)
      |> move(system)
      |> change(system)
      |> stream(system)
    else
      world
    end
  end

  @doc "The world with every automatically updated system one step on."
  @spec step(World.t()) :: World.t()
  def step(%World{part_systems: part} = world) do
    part.systems
    |> Enum.filter(fn {_id, settings} -> settings.automatic_update end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
    |> Enum.reduce(world, &system_update(&2, &1))
  end

  @doc "System `system`'s particles as draw list items, in its draw order (`part_system_drawit`)."
  @spec items(World.t(), non_neg_integer()) :: [map()]
  def items(%World{} = world, system) do
    case Map.fetch(world.part_systems.systems, system) do
      {:ok, settings} ->
        ordered =
          if settings.old_to_new, do: settings.particles, else: Enum.reverse(settings.particles)

        for particle <- ordered,
            settings_of = Map.get(world.part_systems.types, particle.type),
            settings_of != nil,
            item = item(world, particle, settings_of, settings),
            item != nil,
            do: item

      :error ->
        []
    end
  end

  @doc "Every automatically drawn system's particles as draw list items, at the system's depth."
  @spec automatic_items(World.t()) :: [map()]
  def automatic_items(%World{part_systems: part} = world) do
    for {id, settings} <- Enum.sort(part.systems),
        settings.automatic_draw,
        item <- items(world, id),
        do: Map.put(item, :depth, settings.depth)
  end

  defp particle(world, type, settings, {x, y}) do
    {speed, world} = between(world, elem(settings.speed, 0), elem(settings.speed, 1))
    {direction, world} = between(world, elem(settings.direction, 0), elem(settings.direction, 1))
    {angle, world} = between(world, elem(settings.orientation, 0), elem(settings.orientation, 1))
    {life_low, life_high} = settings.life
    {life, world} = between(world, life_low, life_high)
    {colour, world} = first_colour(world, settings.colour)
    {size, world} = between(world, elem(settings.size, 0), elem(settings.size, 1))
    {frame, world} = start_frame(world, settings.random_frame)
    {ran, world} = draw_int(world, 100_000)

    particle = %{
      type: type,
      age: 0,
      life: trunc(life),
      x: x,
      y: y,
      xprevious: x,
      yprevious: y,
      speed: speed,
      direction: direction,
      angle: angle,
      colour: colour,
      alpha: elem(settings.alpha, 0),
      size: size,
      frame: frame,
      ran: ran
    }

    {particle, world}
  end

  defp start_frame(world, false), do: {0, world}
  defp start_frame(world, true), do: draw_int(world, 10_000)

  defp first_colour(world, {:one, colour}), do: {colour, world}

  defp first_colour(world, {:hsv, {h_low, h_high}, {s_low, s_high}, {v_low, v_high}}) do
    {hue, world} = between(world, h_low, h_high)
    {saturation, world} = between(world, s_low, s_high)
    {value, world} = between(world, v_low, v_high)
    {Colour.hsv(trunc(hue), trunc(saturation), trunc(value)), world}
  end

  defp age(world, system) do
    settings = fetch_system(world, system)

    {kept, spawned} =
      Enum.reduce(settings.particles, {[], []}, fn particle, {kept, spawned} ->
        particle = %{particle | age: particle.age + 1}
        type = Map.get(world.part_systems.types, particle.type)

        cond do
          type == nil -> {kept, spawned}
          particle.life <= particle.age -> {kept, [{:death, particle, type} | spawned]}
          true -> {[particle | kept], [{:step, particle, type} | spawned]}
        end
      end)

    world = put_system_settings(world, system, %{settings | particles: Enum.reverse(kept)})
    spawned |> Enum.reverse() |> Enum.reduce(world, &spawn_from(&2, system, &1))
  end

  defp spawn_from(world, system, {:death, particle, %{death: {death, number}}}) when death != nil,
    do: spawn_count(world, system, particle, death, number, :death)

  defp spawn_from(world, system, {:step, particle, %{step: {step, number}}})
       when step != nil and step != particle.type,
       do: spawn_count(world, system, particle, step, number, :step)

  defp spawn_from(world, _system, _spawn), do: world

  defp spawn_count(world, system, particle, type, number, _kind) when number > 0,
    do: particles_create(world, system, {particle.x, particle.y}, type, number)

  defp spawn_count(world, system, particle, type, number, :death) when number < 0 do
    {chance, world} = draw_real(world, 1)

    if chance * -number == 0.0,
      do: particles_create(world, system, {particle.x, particle.y}, type, 1),
      else: world
  end

  defp spawn_count(world, system, particle, type, number, :step) when number < 0 do
    {chance, world} = draw_real(world, 1)

    if trunc(chance * -number) == 0,
      do: particles_create(world, system, {particle.x, particle.y}, type, 1),
      else: world
  end

  defp spawn_count(world, _system, _particle, _type, _number, _kind), do: world

  defp move(world, system) do
    types = world.part_systems.types

    update_system(
      world,
      system,
      &%{
        &1
        | particles:
            Enum.map(&1.particles, fn particle ->
              moved(particle, Map.fetch!(types, particle.type))
            end)
      }
    )
  end

  defp moved(particle, settings) do
    {_low, _high, speed_increment, speed_wiggle} = settings.speed
    {_low, _high, direction_increment, direction_wiggle} = settings.direction
    {_low, _high, angle_increment, _wiggle, _relative} = settings.orientation
    {gravity, gravity_direction} = settings.gravity

    particle = %{
      particle
      | xprevious: particle.x,
        yprevious: particle.y,
        speed: max(particle.speed + speed_increment, 0.0),
        direction: particle.direction + direction_increment,
        angle: particle.angle + angle_increment
    }

    particle = pulled(particle, gravity, gravity_direction)
    turn = triangle(rem(particle.age + particle.ran * 3, 24) / 6)
    pace = triangle(rem(particle.age + particle.ran * 4, 20) / 5)
    speed = (pace - 1) * speed_wiggle + particle.speed
    heading = radians(direction_wiggle * (turn - 1) + particle.direction)

    %{
      particle
      | x: particle.x + :math.cos(heading) * speed,
        y: particle.y - :math.sin(heading) * speed
    }
  end

  defp pulled(particle, gravity, _direction) when gravity == 0, do: particle

  defp pulled(particle, gravity, direction) do
    heading = radians(particle.direction)
    pull = radians(direction)
    vx = :math.cos(heading) * particle.speed + :math.cos(pull) * gravity
    vy = -:math.sin(heading) * particle.speed - :math.sin(pull) * gravity

    %{
      particle
      | speed: :math.sqrt(vx * vx + vy * vy),
        direction: :math.atan2(-vy, vx) * 180 / :math.pi()
    }
  end

  defp change(world, system) do
    types = world.part_systems.types

    update_system(
      world,
      system,
      &%{
        &1
        | particles:
            Enum.map(&1.particles, fn particle ->
              changed(particle, Map.fetch!(types, particle.type))
            end)
      }
    )
  end

  defp changed(particle, settings) do
    {_low, _high, size_increment, _wiggle} = settings.size
    {start, middle, finish} = settings.alpha
    reached = if particle.life < 1, do: 1.0, else: 2 * particle.age / particle.life

    alpha =
      if particle.life >= 1 and reached < 1,
        do: (1 - reached) * start + middle * reached,
        else: (2 - reached) * middle + (reached - 1) * finish

    %{particle | size: max(particle.size + size_increment, 0.0), alpha: alpha}
  end

  defp stream(world, system) do
    fetch_system(world, system).emitters
    |> Enum.sort()
    |> Enum.reduce(world, fn
      {id, %{stream: {type, number}}}, world when type != nil and number != 0 ->
        emitter_burst(world, system, id, type, number)

      _emitter, world ->
        world
    end)
  end

  defp item(world, particle, settings, system) do
    case World.sprite(world, settings.sprite) do
      nil ->
        nil

      sprite ->
        frames = length(sprite.frames)
        {_low, _high, _increment, size_wiggle} = settings.size
        {_low, _high, _increment, angle_wiggle, relative} = settings.orientation
        {scale_x, scale_y} = settings.scale
        {offset_x, offset_y} = system.position

        size =
          (triangle(rem(particle.age + particle.ran, 16) * 0.25) - 1) * size_wiggle +
            particle.size

        base = if relative, do: particle.angle + particle.direction, else: particle.angle

        angle =
          angle_wiggle * (triangle(rem(particle.age + particle.ran * 2, 16) * 0.25) - 1) + base

        %{
          picture:
            {:sprite, settings.sprite, Integer.mod(frame(particle, settings, frames), frames)},
          origin: sprite.origin,
          position: {particle.x + offset_x, particle.y + offset_y},
          scale: {scale_x * size, scale_y * size},
          angle: angle,
          blend: particle.colour,
          alpha: particle.alpha,
          mode: if(settings.additive, do: :add, else: :over),
          depth: system.depth
        }
    end
  end

  defp frame(particle, %{animate: false}, _frames), do: particle.frame
  defp frame(particle, %{stretch: false}, _frames), do: particle.frame + particle.age

  defp frame(particle, _settings, frames),
    do: div(particle.age * frames, max(particle.life, 1)) + particle.frame

  defp place(world, %{region: {xmin, xmax, ymin, ymax}, shape: shape, distribution: distribution}) do
    {u, v, world} = spread(world, shape, distribution)
    across = if shape == :line, do: u, else: v
    {{(xmax - xmin) * u + xmin, (ymax - ymin) * across + ymin}, world}
  end

  defp spread(world, shape, distribution) do
    {u, world} = distributed(world, distribution)
    {v, world} = distributed(world, distribution)
    {u, v, world} = invgaussian_axis(world, u, v, shape, distribution)

    if outside?(shape, u, v), do: spread(world, shape, distribution), else: {u, v, world}
  end

  defp invgaussian_axis(world, u, v, shape, :invgaussian) when shape != :line do
    {coin, world} = draw_real(world, 1)
    {flat, world} = draw_real(world, 1)
    if coin >= 0.5, do: {u, flat, world}, else: {flat, v, world}
  end

  defp invgaussian_axis(world, u, v, _shape, _distribution), do: {u, v, world}

  defp outside?(:ellipse, u, v), do: (u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5) > 0.25
  defp outside?(:diamond, u, v), do: abs(u - 0.5) + abs(v - 0.5) > 0.5
  defp outside?(_shape, _u, _v), do: false

  defp distributed(world, :linear), do: draw_real(world, 1)

  defp distributed(world, :gaussian) do
    {value, world} = bell(world)
    {(value + 3) / 6, world}
  end

  defp distributed(world, :invgaussian) do
    {value, world} = bell(world)
    {if(value < 0, do: value + 6, else: value) / 6, world}
  end

  defp bell(world) do
    {first, world} = draw_real(world, 1)
    value = (first - 0.5) * 6
    {chance, world} = draw_real(world, 1)
    if :math.exp(value * value * -0.5) <= chance, do: bell(world), else: {value, world}
  end

  defp between(world, low, high) when high - low > 0 do
    {value, world} = draw_real(world, 1)
    {value * (high - low) + low, world}
  end

  defp between(world, low, _high), do: {low, world}

  defp draw_real(world, n) do
    {value, random} = Random.random(world.random, n)
    {value, %{world | random: random}}
  end

  defp draw_int(world, n) do
    {out, random} = Random.next(world.random)
    {rem(out, n), %{world | random: random}}
  end

  defp triangle(phase) when phase > 2, do: 4 - phase
  defp triangle(phase), do: phase

  defp radians(degrees), do: degrees * :math.pi() / 180

  defp fetch_system(%World{part_systems: part}, system), do: Map.fetch!(part.systems, system)

  defp put_system_settings(%World{part_systems: part} = world, system, settings),
    do: %{world | part_systems: %{part | systems: Map.put(part.systems, system, settings)}}

  defp update_system(world, system, fun),
    do: put_system_settings(world, system, fun.(fetch_system(world, system)))

  defp put_system(world, system, key, value),
    do: update_system(world, system, &Map.put(&1, key, value))

  defp update_emitter(world, system, emitter, fun),
    do: update_system(world, system, &%{&1 | emitters: Map.update!(&1.emitters, emitter, fun)})

  defp update_type(%World{part_systems: part} = world, type, fun),
    do: %{world | part_systems: %{part | types: Map.update!(part.types, type, fun)}}

  defp put_type(world, type, key, value), do: update_type(world, type, &Map.put(&1, key, value))
end
