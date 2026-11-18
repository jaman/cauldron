# Projections

A Cauldron2D world is a grid of tiles. A projection is how that grid becomes a picture:
straight down, from an angle, from the ground, or from inside it. The game writes the
same scene for all five; only the look changes.

`Cauldron2D.Draw.projections/0` answers the five: `:top`, `:oblique`, `:iso`, `:mode7`
and `:first_person`. `Cauldron2D.Draw.picture/3` draws a scene in whichever the client's
look names.

## The same world, five ways

| projection | you see | standing art | turns | camera given by |
| --- | --- | --- | --- | --- |
| `:top` | the grid from straight above, every tile square | its own picture on its tile | no | `:focus` |
| `:iso` | diamonds, with blocks standing up | a top and two shaded sides | quarter turns by default, any angle when sampled | `:focus` |
| `:oblique` | a square grid from above and in front | a front face with its top above it | `1` or `4` facings | `:focus` |
| `:first_person` | the world from an eye inside it | walls of their storeys, floors to the horizon | continuous | `:position`, `:heading` |
| `:mode7` | a ground plane receding to a horizon | flat, from its `:top` face | continuous | `:position`, `:heading` |

Every projection draws the same `cell` function, movers and volumes; the top-down,
isometric and oblique views also take `:labels`. `Cauldron2D.Draw.projections/0` is the
list; `Cauldron2D.Draw.density/2` says how many pixels a tile is drawn with in each.

## Top-down

The default. `Cauldron2D.Camera.view/1` reads a rectangle of cells around the focus, each
tile is drawn at the atlas's own pixels, and movers are sprites at fractional positions
over the grid. `Cauldron2D.Surface.compose/4` blends each distinct cell once into an ETS
entry keyed by its art and tint, then builds each row by slicing tiles and joining the
slices, so a frame with no movers copies no pixels.

```elixir
Cauldron2D.Camera.view(
  focus: {12.5, 8.5},
  size: {40, 22},
  cell: &MyGame.cell/1
)
```

This is the cheapest projection and the one to reach for when the game is about the map:
roguelikes, puzzles, board games, anything where every tile must be readable at once.

Input maps one to one. A step right on the screen is a step `+x` in the world;
`Cauldron2D.Draw.world_at/3` turns a fraction of the picture back into a world point, and
`Cauldron2D.Camera.tile_at/2` and `Camera.tile_at/3` turn a terminal cell into the world
point under it.

## Isometric

`Cauldron2D.Projection.Iso.compose/2` draws a tile of `t` pixels as a diamond `2t` wide
and `t * tilt` tall, rounded to an even number of pixels so neighbours meet. Standing art
becomes a block with a top and two shaded sides; movers and flat overlays are upright
sprites, painted back to front.

```elixir
Cauldron2D.Projection.Iso.compose(:my_game,
  focus: {12.5, 8.5},
  cell: &MyGame.cell/1,
  size: {320, 200},
  facing: 1,
  facings: 8,
  tilt: 1.0
)
```

`facing` turns the world a quarter turn at a time at the default four facings: at facing
`0`, `+x` runs down-right and `+y` down-left. `:facings` makes a turn of more steps, or `:free` for any
angle. `:shrink` of `2` or `4` draws the whole picture at that fraction of its size, so
the same pixels show more tiles.

The art has to stand up: an art drawn with `height:` storeys and `faces:` shows its top
and sides, the two sides shaded differently. `:tilt` between
`0.5` and `1.5` flattens or steepens the diamond.

Up to 32 facings the view is blitted from stamps, one set per art per facing, built on
first use and kept in the atlas cache. Above 32, and with `facings: :free`, the ground and
the standing arts are sampled a pixel at a time instead; it turns to any angle, and costs
upwards of fifteen times as much a frame.

`Iso.project/3`, `unproject/3` and `tile_at/3` map between picture pixels and world
tiles. `Iso.cells/2` is the cells a picture would show, `ground_map/2` the mapping from
picture pixels to the ground, and `Iso.up/1` the heading a game walks when the player
presses up at the view's facing.

## Oblique

`Cauldron2D.Projection.Oblique.compose/2` keeps the grid square: a tile is `t` wide and
`t * squash` tall, and each storey raises what stands on it by `t * rise`. A wall shows
`rise` of its side and covers the ground behind it; rows are painted back to front.

```elixir
Cauldron2D.Projection.Oblique.compose(:my_game,
  focus: {12.5, 8.5},
  cell: &MyGame.cell/1,
  size: {320, 200},
  squash: 0.5,
  rise: 0.75,
  facings: 4
)
```

`facings` is `1` or `4`. At four the view turns in quarters, which leaves the grid square
on the screen, so nothing is resampled; a mover's pose is read from where it heads on the
screen rather than in the world. At `1` the view is fixed and `:facing` is ignored.

It is the projection for a game that wants readable front faces — a platformer's bricks,
a tactics game's units — without the cost or the art burden of diamonds. Like the
isometric view, it has `project/3`, `unproject/3`, `tile_at/3`, `cells/2` and
`ground_map/2`.

## First person

`Cauldron2D.Projection.FirstPerson.render/2` puts the eye at a position and looks along a
heading. Standing arts become textured walls of their height, floors are textured to the
horizon, and movers and arts of no height are billboards. Everything fades towards the
atlas's void colour with distance.

```elixir
Cauldron2D.Projection.FirstPerson.render(:my_game,
  position: {12.5, 8.5},
  heading: :math.pi() / 2,
  cell: &MyGame.cell/1,
  size: {320, 200},
  eye: 0.6,
  pitch: 0.0,
  fov: 70,
  range: 24
)
```

A wall is the cell's standing arts stacked, base first, each repeated per storey with the
face towards the eye — `:north`, `:east`, `:south`, `:west`, else `:side`. A floor is the
base's `:top` face. An overlay of height `0` stands at its tile's centre and is drawn as a
mover. `:eye` is how far above the ground the eye sits in tiles; `Atlas.eye_height/2`
answers it for an art, so a figure looks out from its own head. `:pitch` moves the horizon,
`:fov` is the horizontal field of view in degrees, and `:range` is where things fade out.

The cost is a ray per column, marching up to the range; the picture is drawn at four
pixels a tile by default and is not zoomed. This is the projection for a game about what
is in front of you: a dungeon crawl, a maze, a corridor. Art needs its `:height` to make
walls rather than billboards; `:faces` gives the walls their texture.

There is no `unproject` here: a point of a first-person picture is not a place on the
ground. Aim along the heading instead, with a ray — `Cauldron2D.Grid.Ray.cast/3` — and
turn held directions to the eye with `Cauldron2D.Walk.relative/2`.

## Mode 7

`Cauldron2D.Projection.Mode7.render/2` draws the ground as a plane in perspective to a
horizon, from a camera above it, turning freely. The plane is sampled from each
cell's `:top` face, so storeys lie flat like any other: this projection has no
verticality. Movers stand on it as billboards, and it fades to the void colour with
distance.

```elixir
Cauldron2D.Projection.Mode7.render(:my_game,
  position: {12.5, 8.5},
  heading: :math.pi() / 2,
  cell: &MyGame.cell/1,
  size: {320, 200},
  eye: 1.6,
  pitch: 0.0,
  fov: 70,
  range: 24,
  sky: {{24, 30, 58}, {96, 120, 170}}
)
```

The heading is continuous, so the view turns by any angle rather than in steps. `:pitch`
moves the horizon, `:aspect` keeps proportions when the picture goes into cells that are
not square, and `:sky` is the colour above the horizon. It is the projection for speed: a
racer, a flight game, a world that is mostly ground. It has `project/3`, `unproject/3` and
`tile_at/3`, the last two answering `nil` at or above the horizon.

## What the art has to give

The projections read these entry fields beyond the sprite:

| field | what it adds | read by |
| --- | --- | --- |
| `:height` | how many storeys the art stands | iso, first person |
| `:faces` | `:top`, `:side`, and compass sides that differ | iso, first person |
| `:poses` | `:front`, `:back` and `:side` pictures | every projection that poses movers |
| `:stand` | how tall it stands as a billboard, in tiles | the perspective projections |
| `:eye` | how high the camera is when put where it stands | first person |

A mover's pose comes from its heading: towards the camera shows `:front`, away shows
`:back`, across shows `:side`, mirrored when it points the other way. An art without
poses falls back to its own picture. `Atlas.face/3` and `Atlas.pose/4` read them;
`Atlas.standing/2` and `Atlas.eye_height/2` answer the heights.

A scene that draws its own frame — a `:picture` function — bypasses all five and is drawn
as the `:picture` projection at its own size or the pane's.

## How input maps to the world

The look decides what "up" means before the game sees the input. `Cauldron2D.Client.Look`
does the turning:

| projection | what the game receives |
| --- | --- |
| `:top` | held actions, as they are |
| `:oblique` at one facing | held actions, as they are |
| `:oblique` or `:iso` at four facings | the four directions turned with the view |
| `:iso` at more or finer facings | held actions plus `:heading`, in radians |
| `:mode7`, `:first_person` | held actions plus `:heading` |

`Look.steered/2` is that step. `Look.world_direction/2` turns a single screen direction
into a world one, and `Look.facings/1` says how many steps the view is turning in. A game
offering more than four facings must read `:heading`: pressing up then moves the same way
across the picture however far the view has turned.

A pointer goes the other way. `Draw.world_at/3` maps a fraction of the picture to the
ground point under it — top-down directly, isometric, oblique and mode 7 through their
`unproject/3` — and answers `nil` in first person. `Cauldron2D.Walk.relative/2` turns held
directions to an eye's heading for a game that walks through one.

## Switching

A game does not switch projections; its look does. `c:Cauldron.Client.Game.look/0` gives
the starting view and the list the player can cycle through:

```elixir
def look do
  %{
    projection: :top,
    projections: [:top, :iso, :oblique, :first_person],
    facing: 0,
    facings: 4,
    tilt: 1.0,
    heading: 0.0,
    pitch: 0.0,
    zoom: 1
  }
end
```

The client's projection key — `v` by default in `Cauldron.Client.Keys`, `Back` on a
controller with a menu and `Start` without one — calls `Cauldron2D.Client.Look.cycle/1`,
which moves to the next of `:projections` and wraps. `[` and `]` turn, `'` and `;` tilt,
and a pointer drag turns where `Look.turns_with_pointer?/1` says it should. The pure
functions are `Look.of/1`, `Look.cycle/1`, `Look.turn/2`, `Look.tilt/2` and `Look.dragged/2`,
so a game can put a view on a menu row or start in a different one per level.

Switching costs nothing but a redraw: the world, the game state and the input are the
same. That is what makes a map view and a first-person view of one world possible in one
game.

## Costs

| projection | cost | zoom levels |
| --- | --- | --- |
| `:top` | one cached blend per distinct cell; slices per row | 4, 2, 1, then 1/2 down to 1/16 |
| `:iso` | stamped up to 32 facings; sampled and ~15× dearer above | 2, 1, 1/2, 1/4 |
| `:oblique` | rows painted back to front; no resampling | 2, 1, 1/2 |
| `:mode7` | every pixel below the horizon sampled | 1 |
| `:first_person` | a ray per column, up to the range | 1 |

`Draw.density/2` decides how many pixels a tile gets before the pane scales the picture:
half the atlas's tile for the isometric and oblique views, four pixels in first person and
mode 7, and the view's own `:density` where the game sets one. The zoom levels are
`Draw.zoom_levels/3`; `Draw.fitting_zoom/3` pulls a zoom back until the tallest art fits.

On a terminal with no pixel protocol, the isometric and oblique views can also be drawn as
the atlas's two-character glyphs, with `Cauldron2D.Projection.Glyphs.compose/3`.

## Where next

- [Art: atlases, pictures and fonts](atlas-and-art.html): what the projections draw, and
  the fields they read.
- [Maps and grids](maps-and-grids.html): the world the camera moves over.
- [Physics](physics.html): moving through it.
- [Your first game](tutorial.html): a scene drawn in the top-down view.
