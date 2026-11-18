# Maps and grids

A Cauldron2D world is a grid, but a game does not have to keep one. It can read a level
file into plain data, ask a function what is at a tile, and let the engine find what can
be seen or where a way goes. Three modules read level files; the grid algorithms take a
function over one tile; the sector maps are not on a grid at all.

## Three ways to have a map

| source | module | best for | what you give up |
| --- | --- | --- | --- |
| text | `Cauldron2D.Map` | tests, prototypes, small levels, hand edits | one character a tile, no layers or objects |
| Tiled | `Cauldron2D.Map.Tiled` | a level made in a graphical editor | you resolve tilesets, layers and collision yourself |
| LDtk | `Cauldron2D.Map.Ldtk` | projects of levels, entities, int grids | the same, plus a project structure to read |
| sectors | `Cauldron2D.Sectors.Map` | arbitrary geometry, floors and ceilings, a Doom-like view | you write the loader; `with_bsp/2` builds the BSP |

All of them return plain data. The engine attaches no meaning to a character, a tile id
or a layer name; the game does.

## Text maps

`Cauldron2D.Map.parse/2` reads a grid of characters and the options written above it.
There are two layouts. A bare picture is every line a row:

```
####
#..#
####
```

The other is XPilot's header format: `name: value` lines, then the grid between multiline
markers.

```
mapwidth: 6
mapheight: 3
edgewrap: yes
mapData: \multiline: EndOfMapdata
xxxxxx
x _  x
xxxxxx
EndOfMapdata
```

The engine reads only three options: `mapwidth` and `mapheight` size the grid, and the
option named by `:wrap` makes it wrap. Everything else is the game's:

```elixir
{:ok, map} = Cauldron2D.Map.parse_file("priv/maps/cavern.map", wrap: "edgewrap")

legend = fn
  "#" -> {:wall, :stone}
  "." -> :floor
  "~" -> :water
  _ -> nil
end

cells = Cauldron2D.Map.cells(map, legend)
spawns = Cauldron2D.Map.positions(map, "@")
```

`Cauldron2D.Map.at/2` is the character at a tile; outside the grid it is a space, or the wrapped tile
when the map wraps. `Cauldron2D.Map.cells/2` calls the legend once per tile and keeps what it answers
unless it is `nil`. `Cauldron2D.Map.positions/2` finds every occurrence of a character, row by row.

`Cauldron2D.Map.option/4` converts a named option to `:string`, `:integer`, `:float` or `:boolean`,
with `yes`, `true`, `on` and `1` true and `no`, `false`, `off` and `0` false. Option names
ignore case. A multiline block with no closing marker runs to the end of the text; a row
wider than `mapwidth` is cut and a shorter one padded. `{:error, :empty}` is no rows at
all.

A `.gz` file is decompressed by `parse_file/2`, which is how XPilot's own maps are kept.

## Tiled

`Cauldron2D.Map.Tiled.read/1` reads a `.tmj` (JSON) or a `.tmx` (XML) orthogonal map,
finite or infinite, into a map a game builds its world from:

```elixir
{:ok, level} = Cauldron2D.Map.Tiled.read("priv/maps/forest.tmj")

ground = Cauldron2D.Map.Tiled.layer(level, "ground").tiles
spawns = Cauldron2D.Map.Tiled.objects(level, "spawns")
```

A level is `%{width, height, tile_width, tile_height, properties, tilesets, layers}`,
sizes in tiles and pixels as Tiled gives them. Each layer is one of three kinds:

| kind | holds |
| --- | --- |
| `:tiles` | `tiles` maps `{x, y}` to the tile's global id, `0` cells left out; `flips` maps a cell to a list of `:horizontal`, `:vertical` and `:diagonal` |
| `:objects` | `objects`, each `%{id, name, type, x, y, width, height, properties}`, place and size in tiles, and `gid` for a tile object |
| `:image` | an `image` for the whole layer |

Layers inside groups are listed with their group's name before theirs, `"group/layer"`.
Properties are maps from name to value, typed as Tiled types them. Tile data may be a
list or base64, uncompressed or compressed with zlib or gzip; other compressions are not
read. A tileset is `%{first_gid, name, columns, count, image}`; an external tileset is named by
its file.

What the module does not do is turn a global id into an atlas art. A game picks the
tileset whose `first_gid` is the highest at or below the id, subtracts it, and maps the
result to its own tile names. That is also where autotiling, collision layers and
one-way platforms become the game's rules rather than the editor's.

## LDtk

`Cauldron2D.Map.Ldtk.read/1` reads an `.ldtk` project, including levels kept in their own
`.ldtkl` files beside it:

```elixir
{:ok, project} = Cauldron2D.Map.Ldtk.read("priv/maps/world.ldtk")
level = Cauldron2D.Map.Ldtk.level(project, "Level_0")
walls = Cauldron2D.Map.Ldtk.layer(level, "Collisions").values
spawns = Cauldron2D.Map.Ldtk.layer(level, "Entities").entities
```

A project is `%{grid_size, levels}`. A level is
`%{name, x, y, width, height, fields, layers}`: its place in the world and its size in
pixels, its custom fields, and its layers from the top down. A layer has `name`,
`columns`, `rows` and `grid_size`, and by its kind:

| kind | holds |
| --- | --- |
| `:int_grid` | `values`, `{x, y}` to the cell's value, with `0` cells left out |
| `:tiles` | `tiles`, each `%{at: {x, y}, tile: id, flips: [...]}`, a cell may hold several |
| `:entities` | `entities`, each `%{id, name, x, y, width, height, fields}`, place and size in cells |

Fields are maps from a field's name to its value. `Ldtk.parse/1` reads a project whose
levels are inside the text; a level file outside it is an error there, while `read/1`
follows it. `Ldtk.level/2` and `Ldtk.layer/2` answer `nil` when the name is not there.

The trade against Tiled is mostly what the editor gives you: LDtk has a project of levels,
integer grids and entity definitions; Tiled has layers, tile layers with flips, and
object properties. Both are JSON or XML; both leave tile ids, collision and spawning to
the game.

## Grids

Whichever map a game has, the algorithms take a function. There are two shapes of it.

For movement and collision, a tile is `:open`, `:solid`, or a half tile
`{:diagonal, :nw | :ne | :sw | :se}`. That is `Cauldron2D.Collision`'s and
`Cauldron2D.Grid.Coarse`'s grid; `Cauldron2D.BoxBody` takes the simpler
`:solid | :platform | :open` one.

For sight and paths, a tile is a boolean: opaque or transparent, walkable or not. A tile
outside the map should answer `false`.

### What can be seen

`Cauldron2D.Grid.Fov.compute/3` is recursive shadowcasting: eight octants, each scanned
row by row away from the observer. An opaque tile splits the wedge and what is behind it
is not visited, so the cost follows what is visible rather than the area of the circle.

```elixir
seen = Cauldron2D.Grid.Fov.compute(&transparent?/1, {12, 9}, 8)
```

Two rules hold: walls bounding a lit area are lit, and visibility is mutual — if `b` is
in the set from `a`, `a` is in the set from `b` at the same radius. `origin` is always in
the set. The radius is Euclidean, not a square.

For one line rather than a field, `Cauldron2D.Grid.Ray.cast/3` walks every tile a line
passes through, corners included, so it cannot slip between two walls that only touch at
a corner:

```elixir
case Cauldron2D.Grid.Ray.cast({archer.x, archer.y}, {hero.x, hero.y}, &solid?/1) do
  :clear -> fire()
  {:hit, _tile, at} -> warn(at)
end
```

`Ray.clear?/3` is the boolean; `Ray.tiles/2` is every tile and the point where the line
enters it, in order. A line starting inside a solid tile hits it at once.

### Finding a way

`Cauldron2D.Grid.Path.find/4` is breadth-first, for the fewest steps;
`Cauldron2D.Grid.Path.astar/4` is A*, for the cheapest by a `:cost` function.

```elixir
{:ok, path} = Cauldron2D.Grid.Path.find(&open?/1, {0, 0}, {5, 2}, size: {6, 5})

{:ok, path} =
  Cauldron2D.Grid.Path.astar(&open?/1, {0, 0}, {5, 2},
    size: {6, 5},
    cost: &terrain/1
  )
```

A path is the cells from the first step to the goal, the start left out; the same cell as
start and goal is `[]`. `:none` is no way within the limit. Options are `:size`
(required), `:wrap?` (whether the edges join), `:neighbours` (`:four` or `:eight`),
`:limit` (cells expanded before giving up, default 10,000), and `:cost` for `astar/4`
only, a positive cost of stepping into a cell. The heuristic follows the neighbours: a
Manhattan distance for four, a Chebyshev one for eight.

`Cauldron2D.Route` is the layer a game usually wants. `Route.to/4` turns a click into the
tile centres to walk through, ending at the point asked for so a mover arrives where it
was sent; `Route.advance/3` moves along the route by a distance, carrying the remainder
into the next step; `Route.heading/2` is the way to the next point; `Route.arrived?/1`
and `Route.goal/1` read it. A route is a plain list of points, so it saves, replays and
pattern matches.

### Coarse grids

A big or open map does not need a tile-by-tile search.
`Cauldron2D.Grid.Coarse.new/3` cuts the grid into blocks of `:block` tiles a side
(default 8) and joins the open tiles of each block into regions. `find/4` searches the
regions for the order to cross them, then the tiles of the first few for the steps, so
the search costs what the regions crossed cost, whatever the grid's size.

```elixir
coarse = Cauldron2D.Grid.Coarse.new(&tile_at/1, {width, height}, wrap?: true)

{:ok, path} = Cauldron2D.Grid.Coarse.find(coarse, me.pos, enemy.pos)
goal = Cauldron2D.Grid.Coarse.waypoint(&tile_at/1, me.pos, path, me.radius)
```

`find/4` returns the points to pass, ending at the target when it lies in the regions
searched. `:ahead` says how many regions past the one the start is in the steps run
through; a way crossing more ends where the last of them meets the next. `waypoint/4`
takes the last point of the path's first stretch that the body can reach in a clear
straight line, so a chaser does not walk to every corner. `reachable?/3` answers whether
a way exists at all. `spots/1` gives one point in the middle of each region, useful for
patrols and spawns.

A step goes to one of the eight tiles around, diagonally only where both tiles beside the
corner are open. Crossing beside a wall costs three times as much, so ways keep off walls
where there is room. On a wrapping grid a path runs on across the edges instead of
jumping back, so points may lie off the grid.

`Cauldron2D.Steer.chase/6` is the cheap alternative when a path is too much: it tries the
eight directions in a preferred order and takes the next best when the best is blocked.
It feels its way round corners without finding a path, and the game supplies the walk
and the random draw. `Steer.vector/1` and `Steer.opposite/1` name the directions.

## Sectors

A sector map is not a grid. It is vertices, lines, sides and sectors, the geometry of a
Doom-like level: rooms of any shape, each with its own floor and ceiling height, joined
and walled by lines. It lives in `Cauldron2D.Sectors.Map`.

```elixir
map = %Cauldron2D.Sectors.Map{
  vertices: {{0.0, 0.0}, {256.0, 0.0}, {256.0, 256.0}, {0.0, 256.0}},
  lines: {%{from: 0, to: 1, front: 0, back: nil, flags: MapSet.new(), special: 0, tag: 0}},
  sides: {%{sector: 0, x_offset: 0.0, y_offset: 0.0, upper: nil, middle: 3, lower: nil}},
  sectors: {%{floor: 0.0, ceiling: 128.0, floor_picture: 5, ceiling_picture: 6,
              light: 160, special: 0, tag: 0}}
}
|> Cauldron2D.Sectors.Map.with_bsp()
```

A **line** runs `from` vertex `to` vertex; its `front` side is on its right looking along
it, its `back` (or `nil` for a wall with nothing behind) on its left. A **side** says
which sector it faces and which pictures it shows: `upper`, `lower` and `middle`. A
**sector** has a `floor` and a `ceiling`, their pictures and a `light` from 0 to 255;
`special` and `tag` are the game's.

A line's `flags` is a set. The engine reads `:blocks`, `:blocks_walkers`,
`:blocks_sound`, `:upper_unpegged`, `:lower_unpegged`, `:secret`, `:hidden` and
`:mapped`; others are the game's.

`with_bsp/2` builds the BSP that orders the level for drawing and for finding a point's
sector. `sector_at/2` and `subsector_at/2` use it; `vertex/2`, `ends/2`, `side_sector/4`
and `sector_lines/2` read the rest. A game that has a level file writes its own loader
into this struct: the package has no WAD reader.

Movement and sight take a `world` of `%{map:, blockmap:, sectors:}`, with the sectors as
they are now, since floors and ceilings move. A view takes the map and an eye carrying
the sectors and sides.

| module | what it does |
| --- | --- |
| `Cauldron2D.Sectors.Blockmap` | files lines and bodies by block (`build/2`, `put_body/2`, `remove_body/2`, `lines_near/3`, `bodies_near/3`) |
| `Cauldron2D.Sectors.Trace` | what a straight line crosses, nearest first (`run/5`, `crossing/4`) |
| `Cauldron2D.Sectors.Move` | `check/4` what a body finds, `try/4` a step, `slide/4` along a wall, `opening/2` a gap's floor and ceiling |
| `Cauldron2D.Sectors.Sight` | whether an eye sees a target through every opening crossed (`visible?/4`) |
| `Cauldron2D.Sectors.Noise` | how far a sound carries through open doors (`index/1`, `spread/3`) |
| `Cauldron2D.Sectors.View` | draws the level from an eye (`render/5`) |
| `Cauldron2D.Sectors.Frame` | an indexed-colour picture drawn a column, a plane or a line at a time (`new/3`, `to_raster/2`) |
| `Cauldron2D.Sectors.Pictures` | the textures and light tables a view draws from (`new/3`, `id/2`, `size/2`) |
| `Cauldron2D.Sectors.Light` | light tables and which one a surface is drawn through (`tables/2`, `table/3`) |
| `Cauldron2D.Sectors.Automap` | the map from above, out of the lines seen so far (`lines/6`, `arrow/3`) |
| `Cauldron2D.Sectors.Overlay` | a picture drawn flat over the view (`columns/4`) |

`Move.check/4` answers a place map — sector, floor, ceiling, drop-off, blocked reason —
without moving anything. `Move.try/4` moves if the body fits, and `Move.slide/4` slides
along whatever stops it, as Doom's player does. `:step` (default 24), `:dropoff`,
`:line_blocks?`, `:body_blocks?` and `:except` decide what counts as a wall and how high a
step is climbed. `Sight.visible?/4` narrows a wedge from the eye to the target's feet and
head, opening by opening; bodies never block sight, and a `:reject` table of sector pairs
skips the work.

Drawing needs a `Cauldron2D.Sectors.Frame` and a `Pictures` set. `View.render/5` takes the
eye's `x`, `y`, `z` and `angle`, the current sectors and sides, and `things` standing in
them; options cover the sky, `:stretch`, `:contrast`, `:extra_light`, a `:fixed` light
table, `:light` and `:fov` (default `π/2`). The frame draws in C where the NIF is loaded —
`Frame.available?/0` says — and in Elixir where it is not, to the same picture. The
returned `seen` set of line indexes is what feeds `Automap.lines/6`.

Sectors are the right choice when the world is rooms with height and occlusion and the
game is about what is behind a door. They are the wrong choice for a tile game: you lose
the grid, the readers above and the simple collision, and you take on BSP construction
and a view renderer of your own.

## Trade-offs

| you want | use | why |
| --- | --- | --- |
| a level in a test, in a dozen lines | `Cauldron2D.Map` | text in, characters out |
| a level an artist edits | Tiled or LDtk | layers, objects, properties, a real editor |
| a big open map with many agents | `Grid.Coarse` | search cost follows the regions crossed |
| a small dungeon, many agents | `Grid.Path` and `Grid.Fov` | one call each, no structure to build |
| a click-to-walk | `Cauldron2D.Route` | paths, steps and headings in one value |
| a chaser that does not path | `Cauldron2D.Steer` | eight directions and a random draw |
| rooms with floors, ceilings and doors | sectors | geometry a grid cannot hold |

The readers are pure and cheap to call once. The grids are functions: keep the level data
in the game's state, and pass a closure over it to whichever algorithm needs one.

## Where next

- [Art: atlases, pictures and fonts](atlas-and-art.html): turning tile ids and layer
  pictures into an atlas.
- [Projections](projections.html): drawing the grid.
- [Physics](physics.html): bodies against the same grids and sectors.
- [Your first game](tutorial.html): a whole game, with a map made of cells.
