# From tiles to an open world

A Cauldron game can start as a grid of tiles and end as a landscape with no edges. The
world module, the client module and the front end stay the same through all of it; what
changes is how much of the world the game describes as data.

The three pictures below are the same camera on three games, drawn by the engine from
data: a grid of tiles, the same grid with art, and an open world with streamed cells.

## 1. Tiles

![A grid of tile ids: grass, a path, a river, and nothing else](assets/stage-tiles.png)

The first version is a table of tile ids. Every tile is the same size, the map is as
large as the table, and a move is from one square to the next.

It is cheap: a screen is a few hundred tiles, a tile is one index into an atlas, and a
whole level fits in memory and is easy to test. `Cauldron2D.Map` reads one from LDtk or
Tiled, `Cauldron2D.Atlas` holds the pictures, and the scene draws the tiles the camera
covers. Movement, collision and line of sight are grid lookups
(`Cauldron2D.Grid`, `Cauldron2D.Collision`).

This is the right start for a puzzle game, a roguelike, or anything where the level is
the design.

## 2. The same world with art

![The same layout with textured ground, trees with shadows, a river and a figure](assets/stage-art.png)

The next version keeps the grid but spends effort on how it looks and moves: an atlas of
drawn art instead of flat colours, trees and rocks as pictures that overlap by depth,
shadows, water, a character with frames, a hud.

Nothing about the map changed. What changed is what the scene is made of:
`Cauldron2D.Picture` cuts frames out of an art file, `Cauldron2D.Atlas.Manifest` derives
a recoloured or turned art from another line by line, the projections
(`Cauldron2D.Projection`) decide the camera, and `Cauldron2D.Draw` turns a view into the
scene a front end draws.

This is where most 2D games live. It is still a grid, still finite, still easy to test.

## 3. An open world

![A sampled height field with a lake, things standing on it, a backdrop wall, the cell grid, and the two rings that load and keep cells](assets/stage-open.png)

The open world drops the grid. The ground is a height field sampled inside square cells,
there is no fixed map size, and the parts of it that exist at any moment are the ones
within reach of a viewer.

`Cauldron.OpenWorld` is that world in `cauldron_core`, with no drawing in it:

* **`Map`** — cells laid edge to edge, put in and taken out one at a time. It knows the
  height at a point, and where a move ends.
* **`Cell`** — one square: ground heights, four kinds of ground, water, the things
  standing in it, and named marks.
* **`Thing`** — a tree, a rock, a signpost: its kind, where it stands, how tall, which
  way it faces, how far it blocks.
* **`Panel`** — a standing picture at the edge of what is simulated, so the country
  beyond can be seen and never reached.
* **`Edge`** — the behaviours that stop a mover where the simulation ends.
* **`Window`** — which cells to hold while viewers move; `load` is what is wanted,
  `keep` what is held until it is far enough away to drop.
* **`Mover`** — walking, climbing, jumping, swimming and falling over the ground.
* **`Store`** — where cells come from: memory, files, or the game's own generator.

```elixir
map =
  Cauldron.OpenWorld.Map.new(
    cell_size: 64.0,
    samples: 64,
    edges: [{Cauldron.OpenWorld.Edge.Scenery, margin: 1.0}]
  )

cell =
  Cauldron.OpenWorld.Cell.sampled(
    {0, 0},
    64,
    64.0,
    fn {x, y} -> 8.0 + 3.0 * :math.sin(x / 9.0) + 2.0 * :math.cos(y / 7.0) end,
    water: 6.0,
    things: [
      %Cauldron.OpenWorld.Thing{kind: :pine, position: {12.5, 40.0}, radius: 0.4}
    ]
  )

map = Cauldron.OpenWorld.Map.put(map, cell)
```

Cells around the player are held, and let go, by the window:

```elixir
%{load: to_fetch, drop: to_forget, held: held} =
  Cauldron.OpenWorld.Window.step(held, map, [{130.0, 40.0}], load: 200.0, keep: 260.0)
```

The two dashed rings in the picture are `load` and `keep`. Where the simulation ends, an
edge stops the mover, and a panel shows what lies beyond. A mover walks the ground rather
than a grid:

```elixir
mover = Cauldron.OpenWorld.Mover.new({12.5, 40.0}, map)
mover = Cauldron.OpenWorld.Mover.step(mover, map, intent, pace, seconds)
{endpoint, stopped?} = Cauldron.OpenWorld.Map.travel(map, mover.point, wanted)
```

A game can introduce the open world without rewriting itself. The world module still
implements `Cauldron.Game`; only `view/2` returns something else, and the client module's
`scene/2` draws that instead. `cauldron_examples/3d/vale` is a complete open world —
eight cells of 64 metres, six by six simulated, a ring of country seen and never reached,
four painted panels — and its map fits in one module, `Vale.Land`.

## What to choose

| | Tiles | Tiles with art | Open world |
| --- | --- | --- | --- |
| The level is | a table of ids | a table of ids | generated or stored cells |
| Size | what fits in memory | what fits in memory | as far as a viewer walks |
| Movement | square to square | square to square, or free on the grid | over ground heights |
| Cost | a screen of tiles | an atlas and a scene | a store, a window and a mover |
| Good for | puzzles, roguelikes | most 2D games | exploring, landscapes, 3D |

The step from one to the next is a change of data, not of contract. That is the point of
keeping the world module pure: the game can grow a landscape without any front end
learning about it.
