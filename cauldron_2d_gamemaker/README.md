# Cauldron2D.GameMaker

Reads the data file of a game made with GameMaker into Elixir structures a
[`cauldron_2d`](https://hexdocs.pm/cauldron_2d) game can use: sprites and their
collision masks, texture pages, tilesets, objects and their events, rooms with their
instances, tiles and layers, sounds, fonts, paths and scripts.

No game files are included. Point it at the data file of a game you own.

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_gamemaker, "~> 0.2"}
  ]
end
```

## Reading a game

```elixir
{:ok, data} = Cauldron2D.GameMaker.Data.read("path/to/data.win")

data.general.format
data.rooms |> Enum.map(& &1.name)

{:ok, pictures} = Cauldron2D.GameMaker.Pictures.new(data)
frames = Cauldron2D.GameMaker.Pictures.sprite(pictures, hd(data.sprites))
```

```sh
mix gamemaker.info path/to/data.win
mix gamemaker.info path/to/data.win --list objects
```

The data file is `data.win` on Windows, `game.ios` in a macOS or iOS bundle's
`Resources`, `game.unx` on Linux and `game.droid` on Android; all have the same layout.

| module | what it reads |
| --- | --- |
| `Data` | the whole file: every resource below, in the game's own order, so a resource's index is its place in its list |
| `General` | the game's name, window, room order, frame rate and which GameMaker built it (`:gms1`, `:gms2`, `:gms2_3`) |
| `Options` | display settings and the game's constants |
| `Sprite` | frames, origin, collision box and per-pixel masks as `Cauldron2D.Mask`s (`mask/2`) |
| `Region`, `Texture` | where a picture sits on a texture page, and the page itself |
| `Pictures` | every page decoded once, and any region, sprite, background or tile cut from them as a `FrenchCurve.Raster` |
| `Background` | GameMaker Studio 1 backgrounds and GameMaker Studio 2 tilesets (`tile_source/2`) |
| `Object`, `Event` | objects with parent, depth, physics and events; event type names and the names of compiled event code (`handler_name/3`) |
| `Room` | size, views, instances, and either backdrops and tiles (Studio 1) or layers (Studio 2): `Room.Instance`, `Room.Tile`, `Room.View`, `Room.Backdrop`, `Room.Layer` |
| `Sound` | sounds, and the stored WAVE and Ogg bytes they index, from the data file or from an audio group file beside it (`Data.audio_group/1`) |
| `Font`, `Path`, `Script` | glyphs and kerning, path points, script names |

## Running a game

The game's code is a module implementing `Cauldron2D.GameMaker.Code`: for each
compiled name (`gml_Object_Ball_Step_0`, `gml_Room_rTitle_Create`, …) it returns a
function of the world, the instance running it and the other instance of a collision.

```elixir
world = Cauldron2D.GameMaker.World.new(data, MyGame.Code)
world = Cauldron2D.GameMaker.Step.run(world, %{held: held, pressed: pressed, released: released})
{world, items} = Cauldron2D.GameMaker.Draw.run(world)

table = Cauldron2D.GameMaker.Pictures.table(pictures, data)
raster = Cauldron2D.DrawList.render(items, {320, 200}, &Map.get(table, &1),
  view: {0, 0}, background: Cauldron2D.GameMaker.Draw.background(world))
```

| module | what it does |
| --- | --- |
| `World` | the running game: instances in creation order, create and destroy, events with inheritance (`perform/5`, `inherited/6`), globals, room changes, the outbox |
| `Step` | one step in GameMaker's order: begin step, alarms, keyboard and mouse, step, motion, collisions, end step, animation, room change |
| `Rooms` | leaving and entering rooms: placed instances, creation code, game start, room start and end |
| `Collide` | instance masks, `place/4`, `meeting?/4`, `free?/3` and collision events |
| `Draw` | the frame as a `Cauldron2D.DrawList`: room backgrounds, tiles and layers, instances, draw and draw GUI events |
| `Instance` | GameMaker's built-in instance variables, motion kept in both forms |

## Limits

Files from GameMaker: Studio 1 and GameMaker Studio 2 up to 2.3 are read. Not read:

* **game code.** A game built with the YoYo Compiler keeps its code in its executable
  as native functions named `gml_Object_<object>_<Event>_<subtype>` and
  `gml_Script_<name>`; its data file has no code to read. A game built for the
  GameMaker virtual machine carries bytecode in `CODE`, `VARI` and `FUNC`, which
  `Data.bytecode?/1` detects; running it is not supported
* **QOI texture pages**, written by GameMaker 2022.1 and later; `Texture.decode/1`
  returns `{:error, {:unsupported_encoding, :qoi}}`
* physics (Box2D) objects and rooms, paths followed by instances, timelines, and the
  asynchronous events
* the older `OPTN` layout, the effect, path and sequence layers of rooms, sequences,
  timelines, shaders and extensions
* the layout changes of GameMaker 2022 and later (room layer effects, sprite masks
  sized to the collision box, sound lengths)

## License

MIT
