# Cauldron2D.GameMaker

This package reads the data file of a game made with GameMaker. It turns the file into
Elixir structures that a [`cauldron_2d`](https://hexdocs.pm/cauldron_2d) game can use.
It reads sprites and their collision masks, texture pages, tilesets, objects and their
events, rooms, sounds, fonts, paths and scripts.

No game files are included. Point it at the data file of a game you own.

The package can also run such a game. You write the game's code as Elixir functions.
`World` holds the running game, and `Step` moves it on in GameMaker's event order.
`Draw` gives each frame as a `Cauldron2D.DrawList`.

## How it fits

The draw list and the pictures are `cauldron_2d` types. Call
`Cauldron2D.DrawList.render/4` to turn a frame into a `FrenchCurve.Raster`. You can
show that raster anywhere a raster goes: in the terminal through `cauldron_2d_drafter`,
in a PNG, or in a Livebook cell. Sprite masks are `Cauldron2D.Mask` structs. Texture
pages are decoded by `linocut`.

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:cauldron_2d_gamemaker, "~> 0.3"}
  ]
end
```

## Reading a game

Call `Data.read/1` with the path of the data file:

```elixir
{:ok, data} = Cauldron2D.GameMaker.Data.read("path/to/data.win")

data.general.format
data.rooms |> Enum.map(& &1.name)

{:ok, pictures} = Cauldron2D.GameMaker.Pictures.new(data)
frames = Cauldron2D.GameMaker.Pictures.sprite(pictures, hd(data.sprites))
```

Run `mix gamemaker.info` to see what a data file holds:

```sh
mix gamemaker.info path/to/data.win
mix gamemaker.info path/to/data.win --list objects
```

The data file has a different name on each system, but the same layout:

* `data.win` on Windows
* `game.ios` in the `Resources` of a macOS or iOS bundle
* `game.unx` on Linux
* `game.droid` on Android

| Module | What it reads |
| --- | --- |
| `Data` | Reads the whole file. Each list keeps the game's own order, so a resource's index is its place in its list. |
| `General` | Reads the game's name, window, room order and frame rate. `format` says which GameMaker built it: `:gms1`, `:gms2` or `:gms2_3`. |
| `Options` | Reads the display settings and the game's constants. |
| `Sprite` | Reads frames, origin and collision box. `mask/2` gives a frame's per-pixel mask as a `Cauldron2D.Mask`. |
| `Region`, `Texture` | `Region` says where a picture sits on a texture page. `Texture` is the page itself. |
| `Pictures` | Decodes every page once. Then it cuts any region, sprite, background or tile from them as a `FrenchCurve.Raster`. |
| `Background` | Reads GameMaker Studio 1 backgrounds and GameMaker Studio 2 tilesets. `tile_source/2` finds a tile in a tileset. |
| `Object`, `Event` | `Object` reads objects with their parent, depth, physics and events. `Event` names the event types. `handler_name/3` gives the name of an event's compiled code. |
| `Room` | Reads size, views and instances. A Studio 1 room has backdrops and tiles; a Studio 2 room has layers. See `Room.Instance`, `Room.Tile`, `Room.View`, `Room.Backdrop` and `Room.Layer`. |
| `Sound` | Reads sounds and the WAVE and Ogg bytes they point to. The bytes are in the data file or in an audio group file beside it, which `Data.audio_group/1` reads. |
| `Font`, `Path`, `Script` | Read glyphs and kerning, path points, and script names. |

## Running a game

Write the game's code as a module that implements `Cauldron2D.GameMaker.Code`. Its
`handler/1` takes a compiled name, such as `gml_Object_Ball_Step_0` or
`gml_Room_rTitle_Create`. It returns a function of three arguments: the world, the
instance running the code, and the other instance in a collision. Return `nil` for
names the game has no code for.

Then create the world, step it and draw it:

```elixir
world = Cauldron2D.GameMaker.World.new(data, MyGame.Code)
world = Cauldron2D.GameMaker.Step.run(world, %{held: held, pressed: pressed, released: released})
{world, items} = Cauldron2D.GameMaker.Draw.run(world)

table = Cauldron2D.GameMaker.Pictures.table(pictures, data)
raster = Cauldron2D.DrawList.render(items, {320, 200}, &Map.get(table, &1),
  view: {0, 0}, background: Cauldron2D.GameMaker.Draw.background(world))
```

| Module | What it does |
| --- | --- |
| `Code` | Defines the behaviour for a game's code module. |
| `World` | Holds the running game. It creates and destroys instances, keeps them in creation order, and runs events with inheritance (`perform/5`, `inherited/6`). It also holds globals and room changes. A step puts sounds and other messages in the outbox; `take_outbox/1` empties it. `new/3` takes `:room`, `:pictures`, `:seed` and `:object_depths`. |
| `Step` | Runs one step in GameMaker's order: begin step, alarms, keyboard and mouse, step, motion, collisions, end step, animation, room change. |
| `Rooms` | Leaves and enters rooms. It places instances and runs creation code and the game start, room start and room end events. |
| `Collide` | Builds instance masks and runs collision events. `place/4`, `meeting?/4` and `free?/3` test positions. |
| `Views` | Moves a view to follow its object (`follow/1`). |
| `Draw` | Gives the frame as a `Cauldron2D.DrawList`. `run/1` draws backgrounds, tiles, layers, instances and draw events. `gui/1` runs the draw GUI events, in window pixels. |
| `Text`, `Shapes`, `TileLayers` | Lay out text in a game's fonts and draw ellipses. `TileLayers.raster/3` draws a room's tile layer as one picture. |
| `Surfaces` | Runs the `surface_*` functions. Code draws onto rasters kept by id: `create/3`, `draw/4`, `rasters/1`, `lookup/2`. |
| `Particles`, `PartSystems` | Run `part_particles_create` and the `part_system_*`, `part_type_*` and `part_emitter_*` functions. |
| `Random`, `Colour` | Give GameMaker's random numbers, seeded as `random_set_seed` seeds them, and its colour functions. |
| `Wave` | Reads a stored WAVE sound as `%{rate, channels, pcm}` with `read/1`. |
| `Instance` | Holds GameMaker's built-in instance variables. Motion is kept both as speed and direction and as horizontal and vertical speed. |

## Limits

The package reads files from GameMaker: Studio 1 and from GameMaker Studio 2 up to 2.3.

It does not read these:

* **Game code.** The YoYo Compiler puts a game's code in the executable as native
  functions, named `gml_Object_<object>_<Event>_<subtype>` and `gml_Script_<name>`. The
  data file has no code to read. A game built for the GameMaker virtual machine keeps
  bytecode in `CODE`, `VARI` and `FUNC`. `Data.bytecode?/1` detects it, but the package
  does not run it.
* **QOI texture pages.** GameMaker 2022.1 and later write them, plain or compressed with
  bzip2. `Texture.decode/1` returns `{:error, {:unsupported_encoding, :qoi}}` or
  `{:error, {:unsupported_encoding, :bz2_qoi}}` for them.
* The older `OPTN` layout.
* The effect, path and sequence layers of rooms, and sequences, timelines, shaders and
  extensions.
* The layout changes of GameMaker 2022 and later: room layer effects, sprite masks
  sized to the collision box, and sound lengths.

It does not run these:

* Physics (Box2D) objects and rooms.
* Paths followed by instances.
* Timelines.
* The asynchronous events.

## License

MIT
