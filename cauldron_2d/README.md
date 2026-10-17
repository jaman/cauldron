# Cauldron2D

Cauldron2D is a 2D game engine for the BEAM. You write a game as a value and a few pure
functions. The engine runs it for many players, draws it, and plays its sound. Other
packages put it on screen: in a terminal, in a browser, or in a desktop window.

This package has no terminal and no UI framework in it. You can compose a frame and check
it as bytes in a test, with no app loop and no clock.

## Installation

Add the engine and a front end to your dependencies. The terminal front end is
`cauldron_2d_drafter`. Add `linocut` to draw pictures as text or code, and
`tuning_fork_speaker` to hear sound on this machine.

```elixir
def deps do
  [
    {:cauldron_2d, "~> 0.3"},
    {:cauldron_2d_drafter, "~> 0.2"},
    {:linocut, "~> 0.2"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

The engine depends on `linocut` and `tuning_fork`. It plays sound only when a sink such as
`tuning_fork_speaker` is present.

## A first game

A game implements `Cauldron2D.Game`. Every callback is pure. This one lets each player walk
left and right along a row:

```elixir
defmodule Walk.Game do
  @behaviour Cauldron2D.Game

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

Drive it in a test with `Cauldron2D.Test`. It needs no process and no clock. Fifty ticks at
50 Hz is one second, so the player ends near `x = 9.0`:

```elixir
driver = Cauldron2D.Test.new(Walk.Game, hz: 50)
{:ok, driver} = Cauldron2D.Test.join(driver, :alice, %{username: "alice"})
driver = driver |> Cauldron2D.Test.hold(:alice, [:right]) |> Cauldron2D.Test.tick(50)
Cauldron2D.Test.view(driver, :alice).me.x
```

Run it for real in a `Cauldron2D.World`. Each player joins from its own process with
`Cauldron2D.Player` and receives a frame every tick:

```elixir
{:ok, world} = Cauldron2D.World.start_link(game: Walk.Game, hz: 50)
:ok = Cauldron2D.Player.join(world, :alice, %{username: "alice"})
Cauldron2D.Player.input(world, :alice, %{held: MapSet.new([:right]), aim: nil})

receive do
  {:cauldron_frame, %{tick: tick, view: view, events: events}} -> view.me.x
end
```

To put the game on screen, write a `Cauldron2D.Client.Game` module and run it with
`cauldron_2d_drafter`. Its README continues this example. For the whole path, read
[Your first game](guides/tutorial.md). It builds `examples/cistern` step by step: the game,
its tests, its art, the terminal, sound, more players, the browser and the window.

## How the packages fit

| Package | What it does |
| --- | --- |
| `cauldron_2d` | This package. It runs worlds and players, and draws tiles, sprites and projections. It holds the client contract every front end reads. |
| [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter) | Puts a game in a terminal. It also serves the game over ssh. |
| [`cauldron_2d_net`](https://hexdocs.pm/cauldron_2d_net) | Serves a game to browsers over a Phoenix channel. Elixir clients use it to join worlds on other machines. |
| [`cauldron_2d_wx`](https://hexdocs.pm/cauldron_2d_wx) | Opens a game in a desktop window. |
| [`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu) | Draws a scene's picture on the graphics card. The terminal client uses it when the scene has a `:gpu` function. |
| [`linocut`](https://hexdocs.pm/linocut) | Draws pictures as text or code, and derives one picture from another. |
| [`cauldron_2d_easel`](https://hexdocs.pm/cauldron_2d_easel), [`_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter), [`_web`](https://hexdocs.pm/cauldron_2d_easel_web), [`_kino`](https://hexdocs.pm/cauldron_2d_easel_kino) | Edit an atlas. The editors run in the terminal, in a browser and in Livebook. |
| [`cauldron_2d_gamemaker`](https://hexdocs.pm/cauldron_2d_gamemaker) | Reads the data files of GameMaker games. |

## What a game is

A game is two modules.

`Cauldron2D.Game` is the game itself. It has `init/1`, `join/3`, `leave/2`,
`handle_input/3`, `step/2`, `view/2` and `drain_events/1`, all pure. `step/2` runs once per
tick. `view/2` builds what one player sees, and the world sends it to that player.
`drain_events/1` returns what happened since the last tick, and every player gets it.

`Cauldron2D.World` runs the game. Players join with `Cauldron2D.Player.join/3`, send what
they hold with `Cauldron2D.Player.input/3`, and receive `{:cauldron_frame, %{tick, view,
events}}`. The world takes these options, among others:

* `record: true` keeps a `Cauldron2D.Replay` of joins, leaves and input.
* `tick: :on_input` steps once each time input arrives. Use it for a turn-based game.
* `state:` starts the world from a saved game.
* `follow:` names another world, on this machine or another, to run in step with.
  The game's optional `export/1`, `restore/1` and `checksum/1` callbacks serve it.

Call `pause/1` and `resume/1` to hold a clocked world. Call `stats/1` to see how it keeps up.

`Cauldron2D.Client.Game` tells the front ends how to show the game. It gives the title,
the atlas, the actions and keymaps, the worlds, how a view becomes a scene, the hud, and
the sounds and music. Twelve callbacks are required: `title/0`, `atlas/0`, `actions/0`,
`keymaps/0`, `toggles/0`, `worlds/1`, `scene/1`, `hud/1`, `listener/1`, `sounds/0`,
`music/0` and `cue/2`. The rest are optional and documented on the module.

`cauldron_2d_drafter`, `cauldron_2d_net` and `cauldron_2d_wx` each read that module. Each
shows a title, a lobby, settings, the world, a summary and a guide. A world listed as
`{module, opts}` belongs to one player, and the client starts it. The game's `start/0`
chooses the flow: the title then the lobby, the lobby alone, straight into a world, or a
function of its own.

A scene is a map. It has a `:focus`, `:bounds`, a `:cell` function from a tile to what is
drawn there, and `:movers` for sprites off the grid. It may add `:labels`, `:volumes`,
parallax `:layers` and a `:heading`. A scene with a `:picture` function draws its own frame
instead of using the atlas. A scene with a `:gpu` function also describes that frame for
the graphics card.

## What is in the engine

### Worlds and players

| Module | What it does |
| --- | --- |
| `Cauldron2D.Game` | Defines the callbacks a game implements. |
| `Cauldron2D.World` | Runs a game at a fixed tick for many players, and sends each its own view. |
| `Cauldron2D.Player` | Joins a world, sends input, and leaves. |
| `Cauldron2D.World.Presence`, `Cauldron2D.World.Events` | Tell any process about joins and leaves in every world, and about one world's events each tick. |
| `Cauldron2D.World.Lockstep` | Keeps a following world in step with its host. |
| `Cauldron2D.Worlds` | Lists the worlds a game offers. It starts a world on first use and sweeps it when idle. |
| `Cauldron2D.Distribution` | Hosts worlds for another machine to join over BEAM distribution. |
| `Cauldron2D.Robot` | Runs a computer player. It joins as `{:robot, n}` and decides through a brain module. |
| `Cauldron2D.Replay` | Records joins and input, and rebuilds the same game from them. `Replay.Viewer` plays one back to a watcher. |
| `Cauldron2D.Test` | Drives a game in a test with no world and no clock. |
| `Cauldron2D.Sessions` | Tracks who is logged in on the node, by any kind of client. |
| `Cauldron2D.Stats` | Reports how the node keeps up. |

### Drawing

| Module | What it does |
| --- | --- |
| `Cauldron2D.Atlas` | Holds the tiles. Each has a sprite or frames, a glyph and a colour. Build one in code or load it from a directory of `.png` and `.pic` files. `subscribe/1` reports changes. |
| `Cauldron2D.Sheet` | Packs an atlas onto one raster with an index, for a browser or a window. |
| `Cauldron2D.Surface` | Composites a grid of cells, movers and labels into one raster. |
| `Cauldron2D.Camera` | Picks the part of the world on screen. `Camera.Follow` trails a target and shakes. |
| `Cauldron2D.Renderer` | Detects whether the terminal shows pixels or only glyphs. |
| `Cauldron2D.Projection.Oblique`, `Projection.Iso`, `Projection.Mode7`, `Projection.FirstPerson` | Draw the same world from above and in front, as an isometric picture, as a ground plane in perspective, or from inside it. |
| `Cauldron2D.Projection.Volume` | Tints what is seen through coloured regions of space, in every projection. |
| `Cauldron2D.Parallax` | Draws background layers that each move at their own share of the camera's motion. |
| `Cauldron2D.Render`, `Cauldron2D.DrawList`, `Cauldron2D.Blend`, `Cauldron2D.Fit` | Draw a frame from placed pictures, blend RGBA, and fit a fixed-shape frame into a pane. |
| `Cauldron2D.Minimap` | Draws the whole map in a few rows of braille. |

### Movement and collision

| Module | What it does |
| --- | --- |
| `Cauldron2D.Loop` | Runs a fixed timestep, so game speed does not follow frame rate. |
| `Cauldron2D.Body` | Moves a point mass with a heading: thrust, drag, gravity fields, wrapping. |
| `Cauldron2D.Collision` | Sweeps bodies against a grid of whole and half tiles, and against each other. |
| `Cauldron2D.Shape`, `Cauldron2D.Mask`, `Cauldron2D.Overlap`, `Cauldron2D.Turn` | Test placed, turned and scaled shapes for overlap, pixel by pixel. |
| `Cauldron2D.Particles` | Moves short-lived particles under a cap. |
| `Cauldron2D.Grid.Path`, `Grid.Coarse`, `Grid.Fov` | Find ways across a grid and in blocks, and compute what can be seen. |
| `Cauldron2D.Route`, `Cauldron2D.Steer` | Walk a found route a step at a time, and chase a target round corners. |
| `Cauldron2D.States`, `Cauldron2D.Thinkers` | Run state tables for actors, and things that change by themselves each tick, in a fixed order. |
| `Cauldron2D.Sectors.*` | Run levels made of sectors with their own floor and ceiling heights. They cover the map, BSP, movement, sight, lighting, the automap and the view. |

### Input, sound and files

| Module | What it does |
| --- | --- |
| `Cauldron2D.Input` | Turns key presses and releases into held actions, with tap and toggle fallbacks. |
| `Cauldron2D.Input.Pad` | Maps game-controller buttons and sticks to actions. |
| `Cauldron2D.Audio` | Plays effects placed around a listener, and music in sections and layers, per player. |
| `Cauldron2D.Map` | Reads a tile map as text, as a picture, or in the classic header format, with a legend you supply. |
| `Cauldron2D.Rng` | Keeps a seeded generator in state, so a game is reproducible. |
| `Cauldron2D.Ledger`, `Cauldron2D.Save`, `Cauldron2D.Paths` | Keep results and boards, save games, and say where a game's files live. |
| `Cauldron2D.Beacon` | Finds a server on the local network. |
| `Cauldron2D.Tuning`, `Cauldron2D.Trace` | Hold the numbers a game plays by, and write a trace that `mix cauldron.report` reads. |

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

The result goes to `FrenchCurve.Raster.from_rgba/4`. Movers are sprites at fractional
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

### Music

`Cauldron2D.Audio.Music` plays a piece that the game declares as sections and layers. It
switches sections on bar boundaries with a cross-fade. A layer written as a Strudel chain
is played live, so a cue sounds at the next bar. The player's music level is the master
gain, so a change reaches notes already sounding. A layer given as a score, a function or
PCM (`{:pcm, binary}`) is rendered once and cached, with the cued section first.

## License

MIT
