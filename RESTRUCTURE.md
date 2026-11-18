# Restructure: core, 2D and 3D

The engine grew out of `cauldron_2d`, so the parts every game uses (worlds, input, menus,
sessions, audio, saving) live beside the parts only 2D games use (tiles, atlases, the
software projections). 3D games such as courtyard depend on `cauldron_2d` for the first
kind and draw with `cauldron_gpu`. This document is the plan for separating them.

## Packages and module names

| Package | Modules | Holds |
| --- | --- | --- |
| `cauldron_core` (new) | `Cauldron.*` | Everything not tied to a way of drawing |
| `cauldron_2d` | `Cauldron2D.*` | Tiles, atlases, 2D drawing and projections, 2D physics |
| `cauldron_net` (new) | `Cauldron.Net.*` | Worlds on the network, whatever the game draws with |
| `cauldron_2d_net` | `Cauldron2D.Net.*` | What a 2D frame looks like on the wire, the browser pages, `Serve` |
| `cauldron_3d` | `Cauldron3D.*` | The software 3D renderer, BSP, walk grids, and the scene description |
| `cauldron_3d_scene` (was `cauldron_gpu_scene`) | `Cauldron3D.Scene.*` (was `CauldronGPU.*` structs) | The scene a 3D game describes, drawn by any renderer |
| `cauldron_gpu`, `cauldron_native`, front ends | unchanged prefixes | Renderers and clients |

The Hex name `cauldron` belongs to an unrelated 2017 package; the core's package is
`cauldron_core` and its modules are `Cauldron.*`. A project depending on both would see
two `Cauldron` modules; that is accepted.

The other prefixes stay: `Cauldron2D`, `Cauldron3D`, `CauldronGPU`, `CauldronNative`.

## Where each part of `cauldron_2d` goes

Sorted by what each module depends on (`mix xref graph`) and what it is for.

**Core (`Cauldron.*`).** Running games and players: `Game`, `World` (and `World.Events`,
`Lockstep`, `Pending`, `Presence`, `Rollback`), `Worlds` (and `OnDemand`, `Sweeper`,
`Table`), `Player`, `Robot`, `Loop`, `Link`, `Distribution`, `Beacon`, `Sessions`,
`Chat`, `Stats`, `Replay`, `Replay.Viewer`, `Test`, `Trace` and `mix cauldron.report`.
Input and menus: `Input`, `Input.Pad`, `Presses`, `Menu`, `Menu.Item`. The client side
that every front end shares: `Client.Game`, `Client.Controls`, `Client.Controllers`,
`Client.Fronts`, `Client.Hud`, `Client.Keys`, `Client.Menus`, `Client.Party`,
`Client.Seats`, `Client.Stage`, `Client.Start`, `Front`. Sound: `Audio` (and `Keyed`,
`Music`, `Recording`, `Rendered`). Game state helpers with no geometry: `Rng`, `Timers`,
`Tuning`, `Tween`, `Ease`, `States`, `Thinkers`, `Effects`, `Impact`, `Moves`. Files and
settings: `Launch`, `Paths`, `Save`, `Scores`, `Ledger` (and `Lock`, `Recorder`).

**2D (`Cauldron2D.*`).** Art and drawing: `Atlas` (and `Manifest`, `Tables`), `Sheet`,
`Surface`, `Render`, `Renderer`, `Draw`, `DrawList`, `Blend`, `Mask`, `Screen`,
`Menu.Layout`, `Minimap`, `Fit`, `Parallax` (all), `Projection` (all), `Sectors` (all),
`Camera`, `Camera.Follow`, `Native` (the NIFs). Maps and space: `Map` (and `Ldtk`,
`Tiled`), `Grid` (all), `Route`, `Steer`, `Walk`. Bodies: `Body`, `Box`, `BoxBody`,
`Jump`, `Collision` (and `Buckets`), `Shape`, `Overlap`, `Turn`, `Particles` (and
`Emitter`), `Projectiles` (and `Pattern`), `Steering`. The view behaviour's 2D
implementation (below) and the 2D client contract (`Cauldron2D.Client.Game`).

## Shared interfaces

A behaviour is defined where core code calls something that depends on how a game is
drawn. Where only the game calls it, the 2D and 3D versions stay separate modules.

**The view: `Cauldron.Client.View`.** `Client.Stage`, `Client.Party` and
`Client.Controls` turn the player's look (projection, facing, tilt, heading), step its
zoom and ask how a scene is drawn. Those calls go through the behaviour, which a game
names with `c:Cauldron.Client.Game.view/0`. `Cauldron2D.Client.View` implements it with
today's `Look` (the 2D projections) and `Draw` (zoom levels from the atlas, drawing
props). 2D games `use Cauldron2D.Client.Game`, which declares both behaviours and names
the 2D view.

**The client contract.** `Cauldron.Client.Game` holds the callbacks every game has
(title, actions, keymaps, worlds, scene, hud, sounds, menus, start...).
`Cauldron2D.Client.Game` adds `atlas/0` and the 2D scene's picture fields.

**The hud's colours.** `Client.Hud` names colours by name; resolving a name to RGB is the
front end's job, so the core does not depend on `linocut`.

**Networking: `Cauldron.Net.Drawer`.** The socket, channel, sessions, sound policy, API,
links and load test are generic and live in `cauldron_net`. What a frame is on the wire
(a picture, scene data drawn against an atlas, a 3D change list) is the drawer's. A
session opens its drawer, tells it the client's pane and frame rate, asks it for the
pushes that show each scene from the props the game's view gives, and passes it any
message it does not know (an atlas changing). A link in the same node asks it to turn
pushes into owner messages; a socket link asks it to read them; a link world asks it
what to keep. Sessions, channels and links name it with a `:drawer` option.
`Cauldron2D.Net.Drawer` implements it for 2D games.

**Cameras.** `Cauldron2D.Camera` (which part of a tile world is on screen) and
`Cauldron3D.Camera` (where a picture is taken from) stay separate: no core code calls a
camera.

**Libraries behind Cauldron modules.** A game depends only on Cauldron packages and calls
only Cauldron modules. What it needs from the libraries the engine is built on has a
Cauldron module that delegates to them, with their docs and specs under the Cauldron
name: sound making and music (`Cauldron.Audio.Voice`, `Envelope`, `Filter`, `Curve`,
`Sample`, `Score`, `Part`, `Decoder`, `Sink`, over `tuning_fork`), pictures
(`Cauldron2D.Picture`, `Shapes`, `Raster`, `Font`, over `linocut` and `french_curve`), and
testing in the terminal (`Cauldron2D.Drafter.Test`, over `drafter`). The engine's own
modules use the libraries directly; their public specs name the Cauldron types.

## 3D: one scene, any renderer

`cauldron_gpu_scene` already describes a 3D scene as data (meshes, materials, instances,
lights, cameras, poses) sent as a change list (`Stream`), and every 3D renderer
implements one protocol (`Target`): `cauldron_gpu` (Metal, Vulkan), `cauldron_3d_net`
(browsers) and `cauldron_3d_kino` (Livebook). The steps:

1. Rename it `cauldron_3d_scene`, its description modules `Cauldron3D.Scene.*`.
2. Add capabilities to `Target` (ray tracing, upscaling, frame generation, the largest
   texture), so a game can offer only what the renderer does.
3. A `Target` drawn by `cauldron_3d`'s software renderer, for devices whose graphics card
   will not open. It draws what it can of the description and ignores the rest.
4. A `static` Makefile target for `cauldron_3d`'s NIFs, so the software renderer has its C
   code on phones.
5. Clients choose the renderer: the graphics card when it opens, the software renderer
   otherwise.

A game describes its scene once. A game that wants a hand-made version for one renderer
still supplies it, and that version is used where it applies.

## Order

1. `cauldron_core`, and moving the core modules into it, with every dependent package and
   example following the new names.
2. The view behaviour and the client contract split.
3. The application split: the core starts its own processes, `cauldron_2d` starts the
   atlas tables.
4. `cauldron_3d_scene`, capabilities, the software `Target`, the `cauldron_3d` static
   target, and renderer choice in the clients.
5. The networking split: `cauldron_net` and `Cauldron.Net.Drawer`.

## Where it stands

As of 2026-10-23 all five steps are done.

* `cauldron_core` holds 66 modules under `Cauldron.*`; `Cauldron.Client.View` is
  implemented by `Cauldron2D.Client.View`, and 2D games `use Cauldron2D.Client.Game`;
  the core starts its own processes.
* `cauldron_3d_scene` holds the scene as `Cauldron3D.Scene.*`; `Target` reports
  capabilities; `Cauldron3D.Scene.Software` draws a scene on the CPU; `cauldron_3d` has a
  static target. The phone client (`Cauldron2D.Native.Gpu`) and the terminal client
  (`Cauldron2D.Drafter.Client.SoftwareStage`) fall back to the software renderer when the
  card will not open. The software renderer draws courtyard's scenes at about 5 frames a
  second at 640×360 on an M3 Max, without shadows, so a night scene lit by lamps looks
  brighter than on the card.
* `cauldron_net` holds 23 modules under `Cauldron.Net.*` and the `Cauldron.Net.Drawer`
  behaviour; `cauldron_2d_net` keeps `Drawer`, `Reader`, `RemoteScene`, `Wire`,
  `Drawing`, `Drawn`, `Atlas`, `Scene`, `Picture`, `Pages` and `Serve`. A served game
  plays in a browser, over a socket link with pictures or client-drawn scenes, and over a
  local link.
* Every package and example compiles without warnings and its tests pass.

3D games use the same sessions through `Cauldron3D.Net.Drawer`: each client is sent its
scene's change stream, as bytes for a browser and as terms for a native client.
`cauldron_3d_net`'s own scene channel remains for scenes that are not games.
