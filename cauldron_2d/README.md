# Cauldron2D

Cauldron2D draws 2D games for the BEAM: tile worlds, sprites, atlases and the 2D
projections. You write a game as a value and a few pure functions; the engine it is
built on, [`cauldron_core`](https://hexdocs.pm/cauldron_core), runs it for many players
and plays its sound, and this package draws it. Other packages put it on screen: in a
terminal, in a browser, or in a desktop window.

This package has no terminal and no UI framework in it. You can compose a frame and check
it as bytes in a test, with no app loop and no clock.

## Installation

Add the engine and a front end to your dependencies. The terminal front end is
`cauldron_2d_drafter`. Add `linocut` to draw pictures as text or code, and
`tuning_fork_speaker` to hear sound on this machine.

```elixir
def deps do
  [
    {:cauldron_2d, "~> 0.4"},
    {:cauldron_2d_drafter, "~> 0.4"},
    {:linocut, "~> 0.3"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

This package depends on `cauldron_core` and `linocut`; the core depends on `tuning_fork`
and plays sound only when a sink such as `tuning_fork_speaker` is present.

## A first game

A game implements `Cauldron.Game`. Every callback is pure. This one lets each player walk
left and right along a row:

```elixir
defmodule Walk.Game do
  @behaviour Cauldron.Game

  @speeds %{left: -4.0, right: 4.0}

  @impl true
  def init(_opts), do: %{players: %{}}

  @impl true
  def join(state, id, _props),
    do: {:ok, put_in(state.players[id], %{x: 5.0, held: MapSet.new()})}

  @impl true
  def leave(state, id), do: %{state | players: Map.delete(state.players, id)}

  @impl true
  def handle_input(state, id, %{held: held}), do: put_in(state.players[id].held, held)

  @impl true
  def step(state, dt),
    do: %{state | players: Map.new(state.players, fn {id, player} -> {id, move(player, dt)} end)}

  @impl true
  def view(state, id), do: %{me: state.players[id], width: 12}

  @impl true
  def drain_events(state), do: {[], state}

  defp move(player, dt) do
    dx = player.held |> Enum.map(&Map.get(@speeds, &1, 0.0)) |> Enum.sum()
    %{player | x: player.x + dx * dt}
  end
end
```

Drive it in a test with `Cauldron.Test`. It needs no process and no clock. Fifty ticks at
50 Hz is one second, so the player ends near `x = 9.0`:

```elixir
driver = Cauldron.Test.new(Walk.Game, hz: 50)
{:ok, driver} = Cauldron.Test.join(driver, :alice, %{username: "alice"})
driver = driver |> Cauldron.Test.hold(:alice, [:right]) |> Cauldron.Test.tick(50)
Cauldron.Test.view(driver, :alice).me.x
```

Run it for real in a `Cauldron.World`. Each player joins from its own process with
`Cauldron.Player` and receives a frame every tick:

```elixir
{:ok, world} = Cauldron.World.start_link(game: Walk.Game, hz: 50)
:ok = Cauldron.Player.join(world, :alice, %{username: "alice"})
Cauldron.Player.input(world, :alice, %{held: MapSet.new([:right]), aim: nil})

receive do
  {:cauldron_frame, %{tick: tick, view: view, events: events}} -> view.me.x
end
```

To put the game on screen, write a `Cauldron.Client.Game` module and run it with
`cauldron_2d_drafter`. Its README continues this example. For the whole path, read
[Your first game](guides/tutorial.md). It builds `cauldron_examples/games/cistern` step by step: the game,
its tests, its art, the terminal, sound, more players, the browser and the window.

## How the packages fit

| Package | What it does |
| --- | --- |
| `cauldron_2d` | This package. It runs worlds and players, and draws tiles, sprites and projections. It holds the client contract every front end reads, the renderer every front end draws with (`Cauldron2D.Draw`), and the client modules they share. |
| [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter) | Puts a game in a terminal. It also serves the game over ssh. |
| [`cauldron_2d_net`](https://hexdocs.pm/cauldron_2d_net) | Serves a game to browsers over a Phoenix channel, and to desktop windows over the same socket. Elixir clients use it to join worlds on other machines. |
| [`cauldron_2d_wx`](https://hexdocs.pm/cauldron_2d_wx) | Opens a game in a desktop window. |
| [`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu) | Draws a scene's picture on the graphics card. The terminal client uses it when the scene has a `:gpu` function. |
| [`linocut`](https://hexdocs.pm/linocut) | Draws pictures as text or code, and derives one picture from another. |
| [`cauldron_2d_easel`](https://hexdocs.pm/cauldron_2d_easel), [`_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter), [`_web`](https://hexdocs.pm/cauldron_2d_easel_web), [`_kino`](https://hexdocs.pm/cauldron_2d_easel_kino) | Edit an atlas. The editors run in the terminal, in a browser and in Livebook. |
| [`cauldron_2d_gamemaker`](https://hexdocs.pm/cauldron_2d_gamemaker) | Reads the data files of GameMaker games. |

## What a game is

A game is two modules.

`Cauldron.Game` is the game itself. It has `init/1`, `join/3`, `leave/2`,
`handle_input/3`, `step/2`, `view/2` and `drain_events/1`, all pure. `step/2` runs once per
tick. `view/2` builds what one player sees, and the world sends it to that player.
`drain_events/1` returns what happened since the last tick, and every player gets it.

`Cauldron.World` runs the game. Players join with `Cauldron.Player.join/3`, send what
they hold with `Cauldron.Player.input/3`, and receive `{:cauldron_frame, %{tick, view,
events}}`. The world takes these options, among others:

* `record: true` keeps a `Cauldron.Replay` of joins, leaves and input.
* `tick: :on_input` steps once each time input arrives. Use it for a turn-based game.
* `state:` starts the world from a saved game.
* `follow:` names another world, on this machine or another, to run in step with.
  The game's optional `export/1`, `restore/1` and `checksum/1` callbacks serve it.

Call `pause/1` and `resume/1` to hold a clocked world. Call `stats/1` to see how it keeps up.

`Cauldron.Client.Game` tells the front ends how to show the game. It gives the title,
the atlas, the actions and keymaps, the worlds, how a view becomes a scene, the hud, and
the sounds and music. Twelve callbacks are required: `title/0`, `atlas/0`, `actions/0`,
`keymaps/0`, `toggles/0`, `worlds/1`, `scene/1`, `hud/1`, `listener/1`, `sounds/0`,
`music/0` and `cue/2`. The rest are optional and documented on the module.

`cauldron_2d_drafter`, `cauldron_2d_net` and `cauldron_2d_wx` each read that module. Each
shows a title, a lobby, settings, the world, a summary and a guide. A world listed as
`{module, opts}` belongs to one player, and the client starts it. The game's `start/0`
chooses the flow: the title then the lobby, the lobby alone, straight into a world, or a
function of its own.

The three front ends read the game through the same modules in this package: the picture
comes from `Cauldron2D.Draw`, and the game's title and summary, its menu, the look, the
client's keys, what the player holds, where the client starts and the chat come from the
modules under "The client modules" below. A game's title, menu, `:screen` and
projections therefore look and behave alike in a terminal, a browser and a window. The
"Which front ends read which callbacks" section of `Cauldron.Client.Game` names the
two callbacks some front ends have no use for.

A scene is a map. It has a `:focus`, `:bounds`, a `:cell` function from a tile to what is
drawn there, and `:movers` for sprites off the grid: `{art, {x, y}}`, with a heading in
radians as a third element to turn or mirror it, and `%{tint: name}` as a fourth to shade
it. It may add `:labels`, `:volumes`, parallax `:layers`, a `:heading`, `:screen` (items
fixed to the pane: the hud, menus), and `:subject` (what the focus follows). A scene with
a `:picture` function draws its own frame instead of using the atlas, at its `:native`
size when it gives one. A scene with a `:gpu` function also describes that frame for the
graphics card, at its `:gpu_size` when it gives one. `Cauldron.Client.Game`'s `scene`
type lists every key.

## What is in the engine

### Worlds and players

| Module | What it does |
| --- | --- |
| `Cauldron.Game` | Defines the callbacks a game implements. |
| `Cauldron.World` | Runs a game at a fixed tick for many players, and sends each its own view. |
| `Cauldron.Player` | Joins a world, sends input, and leaves. |
| `Cauldron.World.Presence`, `Cauldron.World.Events` | Tell any process about joins and leaves in every world, and about one world's events each tick. |
| `Cauldron.World.Lockstep` | Keeps a following world in step with its host. |
| `Cauldron.Worlds` | Lists the worlds a game offers. It starts a world on first use and sweeps it when idle. |
| `Cauldron.Distribution` | Hosts worlds for another machine to join over BEAM distribution. |
| `Cauldron.Robot` | Runs a computer player. It joins as `{:robot, n}` and decides through a brain module. |
| `Cauldron.Replay` | Records joins and input, and rebuilds the same game from them. `Replay.Viewer` plays one back to a watcher. |
| `Cauldron.Test` | Drives a game in a test with no world and no clock. |
| `Cauldron.Sessions` | Tracks who is logged in on the node, by any kind of client. |
| `Cauldron.Stats` | Reports how the node keeps up. |

### Drawing

| Module | What it does |
| --- | --- |
| `Cauldron2D.Atlas` | Holds the tiles. Each has a sprite or frames, a glyph and a colour. Build one in code or load it from a directory of `.png` and `.pic` files. `subscribe/1` reports changes. |
| `Cauldron2D.Picture` | Makes pictures for art: sprites written as text, outlines turned to every heading, `.png` and `.pic` files read, and flips, turns, tints, scaling and frames cut from a strip. |
| `Cauldron2D.Shapes` | Draws lines, rectangles, circles and polygons onto a picture. |
| `Cauldron2D.Raster` | A picture's pixels: make one, read and set pixels, crop, convert to and from RGBA bytes. |
| `Cauldron2D.Font` | An atlas's pixel font: how wide and tall text is, where each glyph goes, and the text drawn. |
| `Cauldron2D.Palette` | The colour names pictures and huds use, as RGB. |
| `Cauldron2D.Draw` | Draws a scene as one picture: the world from the atlas in its projection, its parallax layers, movers, labels and volumes, and over them its `:screen` and `:outlines`. Every front end shows this picture. |
| `Cauldron2D.Sheet` | Packs an atlas onto one raster with an index of where each art sits. |
| `Cauldron2D.Surface` | Composites a grid of cells, movers and labels into one raster. |
| `Cauldron2D.Camera` | Picks the part of the world on screen and keeps it inside a level's edges. `Camera.Follow` trails a target, with a deadzone, and shakes. |
| `Cauldron2D.Renderer` | Detects whether the terminal shows pixels or only glyphs. |
| `Cauldron2D.Projection.Oblique`, `Projection.Iso`, `Projection.Mode7`, `Projection.FirstPerson` | Draw the same world from above and in front, as an isometric picture, as a ground plane in perspective, or from inside it. |
| `Cauldron2D.Projection.Volume` | Tints what is seen through coloured regions of space, in every projection. |
| `Cauldron2D.Parallax` | Draws background layers that each move at their own share of the camera's motion. |
| `Cauldron2D.Render`, `Cauldron2D.DrawList`, `Cauldron2D.Blend`, `Cauldron2D.Fit` | Draw a frame from placed pictures, blend RGBA, and fit a fixed-shape frame into a pane. |
| `Cauldron2D.Minimap` | Draws the whole map in a few rows of braille. |

### Movement and collision

| Module | What it does |
| --- | --- |
| `Cauldron.Loop` | Runs a fixed timestep, so game speed does not follow frame rate. |
| `Cauldron2D.Body` | Moves a point mass with a heading: thrust, drag, gravity fields, wrapping. |
| `Cauldron2D.Collision` | Sweeps bodies against a grid of whole and half tiles, and against each other. |
| `Cauldron2D.Shape`, `Cauldron2D.Mask`, `Cauldron2D.Overlap`, `Cauldron2D.Turn` | Test placed, turned and scaled shapes for overlap, pixel by pixel. |
| `Cauldron2D.Particles`, `Particles.Emitter` | Move short-lived particles under a cap, changing art and tint over each one's life; emit them at a rate or in bursts, spread round an angle, at speeds and for times drawn from ranges. |
| `Cauldron2D.Box`, `Cauldron2D.BoxBody` | Test boxes in tile units for overlap, and move a box that walks and falls through tiles: it stops at solid tiles, lands on one-way platforms from above and jumps up through them, and knows when it stands on ground. |
| `Cauldron2D.Jump` | Jump for a body on the ground: coyote time after leaving a ledge, a height set by how long the jump is held, and a fall-speed cap. |
| `Cauldron2D.Walk` | Walk top-down or through an eye: the direction and strength of held actions, turned to where the eye looks, and a step that slides along walls. |
| `Cauldron2D.Projectiles`, `Projectiles.Pattern` | Fly shots — straight, arcing under gravity, or homing — out of time or out of bounds, and settle what each hits, once, piercing or not; fire them in aimed, fan, ring and rain patterns. |
| `Cauldron.Moves` | Time a strike's wind-up, active window and recovery, and pick its animation frame in step with them. |
| `Cauldron.Impact`, `Cauldron.Effects`, `Cauldron.Timers` | Hold the world still a moment and shake the view when a blow lands; age effects that play once; count named countdowns down. |
| `Cauldron2D.Grid.Path`, `Grid.Coarse`, `Grid.Fov` | Find ways across a grid and in blocks, and compute what can be seen. |
| `Cauldron2D.Route`, `Cauldron2D.Steer` | Walk a found route a step at a time, and chase a target round corners. |
| `Cauldron2D.Grid.Ray` | Cast a line across tiles for line of sight and shots that hit at once, every tile it crosses in order. |
| `Cauldron2D.Steering` | Steer things that move freely: seek, flee, arrive, pursue, evade, wander and separation, blended, turned at a limited force. |
| `Cauldron.Ease`, `Cauldron.Tween` | Ease a change along the usual curves, and run a number, point or colour from one value to another over a time. |
| `Cauldron.States`, `Cauldron.Thinkers` | Run state tables for actors, counted in ticks or in seconds with the time spent in each state kept, and things that change by themselves each tick, in a fixed order. |
| `Cauldron2D.Sectors.*` | Run levels made of sectors with their own floor and ceiling heights. They cover the map, BSP, movement, sight, lighting, the automap and the view. |

### Input, sound and files

| Module | What it does |
| --- | --- |
| `Cauldron.Input` | Turns key presses and releases into held actions, with tap and toggle fallbacks. |
| `Cauldron.Input.Pad` | Maps game-controller buttons and sticks to actions; a game without its own map gets its directions on the d-pad and stick and its other actions on the face buttons. |
| `Cauldron.Presses` | Tell presses and releases from held actions step to step, and remember a press briefly, so a jump or a combo pressed a moment early still counts. |
| `Cauldron.Audio` | Plays effects placed around a listener, and music in sections and layers, per player. |
| `Cauldron2D.Map` | Reads a tile map as text, as a picture, or in the classic header format, with a legend you supply. |
| `Cauldron2D.Map.Tiled`, `Cauldron2D.Map.Ldtk` | Read levels made in Tiled (`.tmj`, `.tmx`) and LDtk (`.ldtk`): tile layers, int grids, objects and entities as spawn points in tiles, and their properties. |
| `Cauldron.Rng` | Keeps a seeded generator in state, so a game is reproducible. |
| `Cauldron.Ledger`, `Cauldron.Save`, `Cauldron.Paths` | Keep results and boards, save games, and say where a game's files live. |
| `Cauldron.Scores` | Keep a local high-score table under the game's data directory. |
| `Cauldron.Launch` | Find a run's settings in one order: the option given, the game's saved launch values, the environment, application config, the default. |
| `Cauldron.Beacon` | Finds a server on the local network. |
| `Cauldron.Tuning`, `Cauldron.Trace` | Hold the numbers a game plays by, and write a trace that `mix cauldron.report` reads. |

### The client modules

The front ends call these. A game calls them only when it writes a front end of its own.

| Module | What it does |
| --- | --- |
| `Cauldron.Client.Game` | The client contract. `player_label/2` writes a player's id for a lobby or a chat line, `frame_rates/1` gives the frame rates a settings screen offers, and `padmap/3` gives the controller map a game is played with. |
| `Cauldron.Client.Hud` | Reads the shapes a game's hud comes in. |
| `Cauldron2D.Client.Look` | Holds the view of a world (projection, facing, tilt, heading, pitch) as the game's `look/0` starts it and the player's keys change it, and turns the player's input for the view in force. |
| `Cauldron.Client.Keys` | The client's own keys (back, settings, zoom, the view, the game's menu) with the game's `client_keys/0` over the defaults, and its controller buttons. |
| `Cauldron.Client.Menus` | Opens the game's own menu and feeds it keys, mouse presses and controller buttons. |
| `Cauldron.Client.Start` | Reads where a client starts from the launch's `:start` prop or the game's `start/0`. |
| `Cauldron.Client.Fronts` | Runs the title and summary a game draws itself (`fronts/1`): the front showing, its clock and its scene. |
| `Cauldron.Client.Stage` | A player's client-side state in a world for a client run in Elixir: the look, the client's keys, the game's menu and options, and the effects the host carries out (sounds, pause, leave, a move to another screen or world). |
| `Cauldron.Client.Controls` | Reads what a player holds from raw key, mouse and controller events, with the player's bindings and the game's toggles, steering and input options. |
| `Cauldron.Client.Party` | The players a client plays on one machine: the player's own controls, the further seats of the game's `local_seats/1`, and which controller plays whom. |
| `Cauldron.Client.Seats` | The further players on one machine, each joined to the world with its own keys and controller. |
| `Cauldron.Client.Controllers` | Names the controllers a client has seen and gives each a player, from the player's assignments. |
| `Cauldron.Chat` | Chat rooms for a served game: `:lobby`, and `{:world, id}` for a world's players, `id` the world's id as a string. The `:cauldron_2d` application starts it. |

Every client names the chat rooms alike, so a terminal, a desktop and a browser in one
world talk in one room. A game turns the chat off with `chat?/0`:

```elixir
Cauldron.Chat.join(:lobby)
Cauldron.Chat.say(:lobby, "alice", "hello")

receive do
  {:chat, :lobby, %{from: from, text: text}} -> {from, text}
end
```

`Cauldron.Chat.history/1` gives a room's last 100 messages, oldest first.

## Common tasks

### Facing and mirroring

Draw every art facing right, along `+x`. A mover given a heading,
`{art, {x, y}, heading}`, is turned by it: a heading pointing left (`:math.pi()`)
mirrors the art. An art with poses (`Cauldron2D.Atlas.put/4`'s `:poses`, or the
`atlas.txt` poses field) shows its `:front`, `:back` or `:side` picture by where the
heading points against the view, mirrored for the other way. Every projection but the
plain glyph one draws facing this way.

    movers: [{:hero, {hero.x, hero.y}, if(hero.facing == 1, do: 0.0, else: :math.pi())}]

### Seeing hit boxes

A scene's `:outlines`, `[{{left, top, right, bottom}, {r, g, b, a}}]` in world tiles,
are drawn as boxes' edges over everything. Put the game's hit boxes, hurt boxes and
triggers there behind a key of its own (`client_keys/0`'s `{:look, :boxes?}` flips a
boolean the scene reads from the look) to see what collides while building it.

### Animating by state

An art with frames (`:fps`, or cut from a strip) loops on the clock by itself. For an
animation that follows what a thing is doing, keep one art per state (`:hero_run`,
`:hero_jump`) and pick it in the scene. For a strike that should show its full swing
while it can hit, `Cauldron.Moves.frame/3` picks the frame from the move's wind-up,
active window and recovery; for something that plays once, `Cauldron.Effects.frame/3`
picks it from its age.

### Menus and screens the game draws

`Cauldron.Menu` runs a menu — pages of `Cauldron.Menu.Item` rows (actions, pages,
toggles, choices, sliders, key bindings, typed text, notes) — with nothing about how it
looks; `Cauldron.Client.Game`'s `open_menu/1` and `menu_event/3` hand it to the
client, and the game draws it in `scene/2` with `Cauldron2D.Menu.Layout`. A scene's
`:screen` items (`Cauldron2D.Screen`: art, text in the atlas's fonts, nine-slice panels,
bars, fills) are drawn fixed to the pane, for a hud or a menu. A game that draws its own
title or summary names `Cauldron.Front` modules in `fronts/1`; the client keeps the
moves between screens.

### Two machines, without distribution

`Cauldron.Link` plays two worlds on two machines with rollback over one TCP
connection, carrying only Erlang terms read with `:safe`: the host world listens
(`Link.listen/2`), the other connects (`Link.connect/3`) and starts its world with
`follow: link, rollback: true`. `Cauldron.World.Rollback` describes how input that
arrives late runs frames again, and how the two worlds keep pace.

### The atlas manifest

`atlas.txt` beside an art directory's pictures gives each art, one a line and
tab-separated: its name, glyph (two columns), colour (`#rrggbb`), frames a second, a
derivation from another art, its height in storeys, its faces
(`top=ART side=ART south=ART`), its poses (`front=ART back=ART side=ART`) and how tall
it stands in tiles as a billboard. An empty field leaves that setting to the picture.
`Cauldron2D.Atlas.Manifest` has the details and examples.

## How drawing works

### The scene is a function

The game owns its entities, combat, generation, turns and saving. The engine draws a grid
of tiles. The two meet in one function:

```elixir
Cauldron2D.Camera.view(
  focus: {x, y},
  size: {columns, rows},
  cell: fn {x, y} -> cell end
)
```

The camera calls `cell` once for each visible tile. A roguelike's `cell` reads its map,
entities and field of view. A brick game's reads a map of bricks.

### Compositing

`Cauldron2D.Surface` touches no pixel per frame for the grid:

* A cell is `{base, overlays, tint}`. Each distinct cell is blended once into an RGBA
  binary and kept in ETS.
* A frame row is built by slicing each tile's row with `binary_part/3` and joining the
  slices. Nothing is copied pixel by pixel.

The result goes to `Cauldron2D.Raster.from_rgba/4`. Movers are sprites at fractional
positions. They are drawn on the rows they cover, so a frame without movers pays nothing
for them.

### Two cells per tile

A tile is two terminal cells wide and one tall. A terminal cell is about twice as tall as
it is wide, so the tile stays square on screen.

### Text mode

On a terminal without a pixel protocol, the same cells are drawn as two-cell coloured
glyphs. `Cauldron2D.Drafter.Surface` can also draw the frame as braille or as block
characters. A mover in text mode lands in the nearest cell, so you need pixels to see
sub-tile positions.

### One picture for every front end

`Cauldron2D.Draw` turns a game's scene and the client's look into one picture:

```elixir
view = Cauldron2D.Draw.new(Cauldron2D.Draw.props(MyGame.Client, scene, look, 1))
raster = Cauldron2D.Draw.picture(view, {40, 22})
```

`picture/3` draws over a pane of `{columns, rows}` tiles at zoom 1 and returns a
`Cauldron2D.Raster` the front end scales to its pane. The top-down view is drawn one
atlas pixel to a raster pixel, the projections at the view's density, and a scene's
`:picture` at its own size. The terminal's surface widget draws with `Draw`'s parts and
adds its stored images and glyphs. The desktop window shows `Draw`'s picture. The browser
shows it as a picture the server sends, or draws the same scene from data with a
JavaScript copy of `Draw` that gives the same bytes (see `cauldron_2d_net`).

### Music

`Cauldron.Audio.Music` plays a piece that the game declares as sections and layers. It
switches sections on bar boundaries with a cross-fade. A layer written as a Strudel chain
is played live, so a cue sounds at the next bar. The player's music level is the master
gain, so a change reaches notes already sounding. A layer given as a score, a function or
PCM (`{:pcm, binary}`) is rendered once and cached, with the cued section first.

## License

[AGPL-3.0-only](https://github.com/jaman/cauldron/blob/main/LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](https://github.com/jaman/cauldron/blob/main/COMMERCIAL.md).
