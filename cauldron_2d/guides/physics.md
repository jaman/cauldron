# Physics: bodies, boxes and what moves them

Cauldron2D does not have a physics engine. It has the pieces a 2D game needs to write
one: a point mass that integrates, a box that walks and falls through tiles, a sweep that
finds a surface, steering behaviours that want a velocity, shots and particles that age.

The rule everywhere is that a step is a pure function of the state and `dt`. The engine
moves values; the game decides what a wall is and what a hit means.

## What moves, and what does not

| module | moves | does not |
| --- | --- | --- |
| `Cauldron2D.Body` | a point mass by thrust, acceleration, drag and gravity fields | collide with anything |
| `Cauldron2D.BoxBody` | a box across and down a tile grid, stopping and landing | apply gravity, handle slopes, or collide with other bodies |
| `Cauldron2D.Collision` | nothing: `sweep/4` reports where a move stops | move the body for you |
| `Cauldron2D.Steering` | an agent toward a wanted velocity, then by it | avoid obstacles |
| `Cauldron2D.Projectiles` | shots by their motion, and ages them | decide what a shot hits |
| `Cauldron2D.Particles` | particles under fields and drag, and ages them | draw themselves |
| `Cauldron2D.Jump` | the body's vertical speed | move the body |

That split is deliberate: a game can use the sweep without the box, the box without the
jump, or none of it.

## A point mass

`Cauldron2D.Body` is `pos`, `vel`, a `heading` index into `headings` directions, `mass` and
`radius`. Positions are tiles, velocities tiles a second. Heading 0 points right and
headings increase counter-clockwise on screen, so a quarter of them points up.

```elixir
body =
  Cauldron2D.Body.new(pos: {4.0, 4.0}, headings: 64, radius: 0.4)

body =
  body
  |> Cauldron2D.Body.turn(16)
  |> Cauldron2D.Body.thrust(20.0, dt)
  |> Cauldron2D.Body.gravitate([%{pos: {8.0, 8.0}, strength: 6.0, kind: :attract}], dt)
  |> Cauldron2D.Body.drag(0.1, dt)
  |> Cauldron2D.Body.integrate(dt)
  |> Cauldron2D.Body.wrap({64.0, 32.0})
```

| call | does |
| --- | --- |
| `Body.new/1` | a body at rest; `:pos`, `:vel`, `:heading`, `:headings`, `:mass`, `:radius` |
| `Body.turn/2` | turn by heading steps, negative clockwise, wrapping |
| `Body.angle/1`, `Body.direction/1` | the heading in radians, and its unit vector |
| `Body.thrust/3` | accelerate along the heading |
| `Body.accelerate/3` | add an acceleration vector |
| `Body.drag/3` | scale velocity by `exp(-coefficient * dt)` |
| `Body.integrate/2` | move by the velocity |
| `Body.speed/1`, `Body.cap_speed/2` | the speed, and a limit on it |
| `Body.gravitate/3` | apply gravity fields |
| `Body.wrap/2` | bring a body that left a `{width, height}` world back in |

A gravity field is a map with a `:strength` and a `:kind`:

| kind | pulls |
| --- | --- |
| `:attract`, `:repel` | toward or from `:pos`, falling off with the square of the distance and capped within one tile |
| `:clockwise`, `:anticlockwise` | across the line to `:pos`, same falloff |
| `{:uniform, {dx, dy}}` | constantly in one direction |
| `{:toward, {x, y}}` | constantly toward a point, away from it when the strength is negative |

`mass` is not used by `Body`; it is there for a game that trades momentum between bodies.
Nothing in `Body` reads the map, so a body walks through walls until the game sweeps it.

## Boxes and tiles

`Cauldron2D.Box` is axis-aligned boxes in tile units, `{left, top, right, bottom}`, `y`
growing downward. Edges that only meet do not overlap.

`Box.overlap?/2` and `Box.contains?/2` test; `Box.around/2` and `around/3` build a box about
a point; `Box.tile/1` is one tile's box; `Box.tiles/1` is every tile a box overlaps.

`Cauldron2D.BoxBody` is a box that walks and falls: `%{x, y, vx, vy, w, h, grounded?}`,
`{x, y}` the middle of its feet in tiles.

```elixir
grid = fn
  {_x, y} when y >= 10 -> :solid
  {_x, 9} -> :platform
  _ -> :open
end

body = Cauldron2D.BoxBody.new({5.0, 8.0}, {0.8, 1.8})
body = %{body | vy: 30.0}
moved = Cauldron2D.BoxBody.move(body, 0.1, grid)
moved.grounded?
```

The grid is a function from a tile to `:solid`, `:platform` or `:open`. `move/3` moves
across first, stopping at solid tiles, then up or down. Falling, it lands on the top of a
solid tile or a platform; rising, it stops under a solid tile and passes up through
platforms. It moves in steps of at most a fifth of a tile, so a fast body does not pass
through a thin wall. It is grounded when it stands on a solid tile or a platform and is
not rising.

`BoxBody.move/3` moves by the velocity it is given. It does not apply gravity: the game
sets `vy` each tick, with `Cauldron2D.Jump.fall/5` or its own numbers. `BoxBody.box/1` is
the box it takes up, `covers?/2` asks whether it overlaps a tile, and `tiles/1` lists the
tiles it touches.

`Cauldron2D.Jump` is the platform-game jump on top of that:

```elixir
{jump, body} =
  if Cauldron2D.Jump.ready?(jump, body),
    do: Cauldron2D.Jump.launch(jump, body, 26.0),
    else: {jump, body}

body =
  body
  |> Cauldron2D.Jump.fall(MapSet.member?(held, :jump), 75.0, dt)
  |> Cauldron2D.BoxBody.move(dt, grid)

jump = Cauldron2D.Jump.step(jump, body, dt)
```

Coyote time lets a body jump for a moment after it leaves a ledge, rising with the jump
let go falls `cut` times as hard, and falling never passes a maximum. `Jump.ready?/3`,
`launch/3`, `step/3` and `fall/5` are the whole of it; the game keeps the jump value with
the body. `Cauldron.Presses.buffered?/4` is what makes a jump pressed just before landing
still count.

`Cauldron2D.Walk` is for the games that do not use a velocity at all: it turns held
actions into a direction, reads how hard a stick pushes, turns the direction to an eye's
heading, and slides a step along walls.

`Walk.direction/2` takes the action-to-step map, default
`%{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}`. `Walk.relative/2` turns the
step to the eye. `Walk.slide/4` tries the full step, then only across, then only along,
and is `:blocked` when no part of it is open.

## Sweeping against tiles

`Cauldron2D.Collision` knows the same tile grid, with half tiles: `:open`, `:solid`, or
`{:diagonal, :nw | :ne | :sw | :se}` for the half toward that corner.

```elixir
case Cauldron2D.Collision.sweep(grid, body.pos, next, body.radius) do
  {:clear, at} ->
    %{body | pos: at}

  {:blocked, at, normal, _cell} ->
    %{body | pos: at, vel: Cauldron2D.Collision.bounce(body.vel, normal, 0.4)}
end
```

`sweep/4` moves from one point to another in steps no longer than a quarter tile, with a
centre sample and a ring of eight around the body's radius. It answers the last clear
point, the normal of the surface struck and the tile it would have entered. A body already inside a
wall is blocked where it is, with a normal opposing its motion. `bounce/3` reflects a
velocity off that normal, keeping the part along the surface and scaling the part into it
by the restitution.

`Collision.inside?/2` is whether a point is in solid material, `cell_of/1` the tile a
point is in, `circles_overlap?/4` and `distance_sq/2` the cheap body-to-body tests.
`Cauldron2D.Collision.Buckets` is the broadphase: `new/1` a bucket size, `insert/4` a
body, `near/3` ids within a reach, `pairs/1` every overlapping pair once. Build it fresh
each tick; there is no removal. Its bucket size should be at least the largest radius plus
the largest reach queried.

## Pixel shapes

When rectangles are not enough, a shape is tested pixel by pixel. `Cauldron2D.Shape` is a
form — `{:rectangle, width, height}` or `{:mask, mask}` — placed at a world position,
with an origin, a per-axis scale (negative mirrors) and an angle in degrees
counter-clockwise.

Two shapes overlap when some world pixel's centre lies inside both. `Overlap.point?/2`,
`rectangle?/2`, `circle?/3` and `line?/3` are the queries; a circle covers the pixel
centres within its radius, and a line is sampled every half pixel. `Shape.contains?/2`
answers for one shape, `Shape.bounds/1` for its rectangle, and `Mask.from_raster/2` and
`Mask.set?/2` make and read the solid pixels of a picture.

This is exact and slow. Call `Shape.bounds/1` first where a game can, and keep pixel
tests for the few things that need them: a shaped hit box, a sloping ramp, a bullet
against a sprite.

## Steering

`Cauldron2D.Steering` is the Reynolds behaviours for things that move freely. Each gives
the velocity an agent wants; `steer/4` turns the agent's velocity toward it no faster than
its force allows, then moves it.

```elixir
wanted =
  Cauldron2D.Steering.blend([
    {Cauldron2D.Steering.seek(bat, {hero.x, hero.y}, 6.0), 1.0},
    {Cauldron2D.Steering.separation(bat, others, 3.0, 4.0), 1.5}
  ])

bat = Cauldron2D.Steering.steer(bat, wanted, 20.0, dt)
```

| call | wants |
| --- | --- |
| `Steering.seek/3`, `flee/3` | straight toward, or away from, a point |
| `Steering.arrive/4` | toward a point, slowing to stop on it |
| `Steering.pursue/3`, `evade/3` | toward or away from where an agent will be |
| `Steering.separation/4` | away from neighbours, harder the nearer |
| `Steering.wander/4` | an aimless drift, its heading jittered from `Cauldron.Rng` |
| `Steering.blend/1` | the weighted sum of wanted velocities |
| `Steering.steer/4` | the velocity turned toward the wanted one, then the move |

`wander/4` returns the velocity, the new heading and the generator, so the game keeps
both. `Steering` does not look at the map, so a steering bird flies through a wall unless
the game sweeps it or adds an avoidance behaviour of its own.

`Cauldron2D.Steer.chase/6` is the grid alternative: eight directions, tried in a
preferred order, taking the next best when the best is blocked. It feels its way round a
corner rather than finding a path, and the game supplies the step and the random draw.

## Shots

`Cauldron2D.Projectiles` keeps shots as plain maps with `:x`, `:y`, `:vx` and `:vy`, plus
whatever the game wants — damage, owner, kind. The keys the module reads are `:motion`,
`:ttl`, `:age`, `:pierce?` and `:struck`.

| motion | flies |
| --- | --- |
| `:straight` (default) | by its velocity |
| `{:arc, gravity}` | by its velocity, then falling at `gravity` |
| `{:homing, speed, turn}` | easing each second by `turn` of the way toward `speed` at its target |

```elixir
shots =
  Cauldron2D.Projectiles.step(world.shots, dt,
    target: &nearest_foe(world, &1),
    keep?: &on_screen?(world, &1)
  )

{world, shots} =
  Cauldron2D.Projectiles.resolve(shots, world, &foe_in_reach/2, &damage_foe/3)
```

`step/3` moves each shot, ages it, drops it when its age reaches its `:ttl`, and keeps it
while `keep?` is true. `move/3` is one shot alone. `resolve/4` walks the shots in order,
calling the game's `find` for what a shot hits and the game's `on_hit` to change the world;
because each hit is settled before the next shot is looked at, a thing destroyed by one
shot is not hit by the next. A shot that hits goes, unless it pierces: then it stays with
the id in its `:struck`, and `struck?/2` is how `find` skips what it has already hit.

`Cauldron2D.Projectiles.Pattern.fire/5` fires the shapes: `{:aimed, n, arc}`,
`{:fan, n, arc}`, `{:ring, n}` and `{:rain, n}`, with `:heading` and `:phase`.

```elixir
shots = Cauldron2D.Projectiles.Pattern.fire({:ring, 12}, {x, y}, nil, 6.0, phase: clock * 1.3)
```

## Particles

`Cauldron2D.Particles` is a capped list of short-lived sprites: `%{art:, pos:, vel:, ttl:}`,
optionally with `:life`, `:arts` and `:tints` to change as it ages. When spawning would
exceed the cap, the oldest go first.

```elixir
particles =
  Cauldron2D.Particles.new(300)
  |> Cauldron2D.Particles.spawn(made)
  |> Cauldron2D.Particles.step(dt, fields: gravity, drag: 0.5)

movers = Cauldron2D.Particles.movers(particles, {-0.5, -0.5})
```

`Particles.step/3` moves every particle with the same `Body` arithmetic — fields, drag,
integration — and drops those whose time is up. `Particles.movers/2` gives the particles
as scene movers, oldest first, each position shifted by an offset that turns a particle's
centre into the top-left corner a sprite is drawn from; `{-0.5, -0.5}` centres a one-tile
sprite. `Particles.spent/1` is how much of a particle's life is gone and `count/1` how
many are alive.

`Cauldron2D.Particles.Emitter` makes them at a rate or in a burst, with the ranges filled
in from the game's generator:

```elixir
sparks = %Cauldron2D.Particles.Emitter{
  at: {4.0, 3.0},
  rate: 30.0,
  angle: -:math.pi() / 2,
  spread: 0.8,
  speed: {2.0, 4.0},
  ttl: {0.3, 0.6},
  arts: [:spark_bright, :spark, :spark_dim],
  tints: [:hot, :warm, :dim]
}

{made, sparks, rng} = Cauldron2D.Particles.Emitter.emit(sparks, dt, rng)
```

`:at` is where they start, `:rate` how many a second, `:angle` and `:spread` in
radians, a speed and a time drawn from `{least, most}`, and an art or a list of arts and tints that change
over each particle's life. `emit/3` keeps what it owed between steps, so a rate slower than
the tick still produces particles; `burst/3` makes a count at once. Both take and return
`Cauldron.Rng`, so a replay makes the same sparks.

## Time

Every stepping function here takes `dt` and nothing reads a clock. `Cauldron.World` runs a game at
a fixed tick, so a game's `step/2` gets the same `dt` every time and physics does not
follow the frame rate. A game with its own loop can use
[`Cauldron.Loop`](https://hexdocs.pm/cauldron_core/Cauldron.Loop.html), which advances a
fixed step and says how long to wait; `Loop.dt/1` is the `dt` to pass on. Running at 30 or
60 ticks a second changes how many steps happen a second, not how fast a body moves.

## What the engine does not do

- No rigid-body solver: no impulses, constraints, friction or resting contacts.
- No collision response inside `Body`; `Collision.sweep/4` reports, and the game decides.
- No body-against-body sweep. `circles_overlap?/4` and `Buckets` test overlap; resolving
  it is the game's.
- No slopes in `BoxBody`: tiles are solid, platform or open, and a half tile is
  `Collision`'s, not the box's.
- No automatic hit detection in `Projectiles`: `resolve/4` is given the game's `find`.
- No obstacle avoidance in `Steering`, and no path in `Steer.chase/6` — it is a heuristic.
- No drawing of particles; `Particles.movers/2` gives the scene movers.
- No global tuning: speeds, forces and caps are the numbers a game passes.

## Costs

| system | what a tick costs |
| --- | --- |
| `Body` | a handful of arithmetic per body |
| `BoxBody.move/3` | one substep per fifth of a tile moved, each over the box's tiles |
| `Collision.sweep/4` | a quarter-tile step, nine samples each |
| `Buckets` | a bucket's neighbours per body, then circle tests |
| `Shape` and `Overlap` | the pixels in the overlap of two bounds |
| `Projectiles.step/3` | the shots, plus whatever `keep?` does |
| `Projectiles.resolve/4` | the shots times whatever `find` does |
| `Particles.step/3` | one particle's arithmetic each, up to the cap |

The expensive numbers are the ones a game chooses: the radius a sweep samples, the cost
of a `find` in a projectile, the cap on particles. The engine's own work is linear in the
things it is given.

## Where next

- [Maps and grids](maps-and-grids.html): the tile grids and sector maps these bodies move
  through.
- [Projections](projections.html): how bodies and shots are drawn.
- [Art: atlases, pictures and fonts](atlas-and-art.html): what a particle's art is.
- [Your first game](tutorial.html): a game that moves its own keeper, without any of this.
