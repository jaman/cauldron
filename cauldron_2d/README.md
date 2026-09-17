# Cauldron2D

A 2D game engine for the BEAM: terminal first, with the browser and the desktop as
front ends. A game is a value and a few pure functions; the engine draws it, runs it for
many players, plays its sound and puts it on screen wherever you point it.

## Getting started

```elixir
def deps do
  [
    {:cauldron_2d, "~> 0.1"},
    {:cauldron_2d_drafter, "~> 0.1"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

Then read [Your first game](tutorial.md): it builds a small game from nothing — the game
as a value, its tests, its art from `.pic` files, the terminal front end with settings
and a hud, sound and music, a second player and a robot, the browser and the window —
and every step is a working example in the repository.

The pieces, and where they live:

| package | what |
|---|---|
| `cauldron_2d` | this package: the engine — tiles, sprites, camera, physics, input, worlds, players, replay, audio, the client contract |
| [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter) | the terminal: a surface widget and a ready-made client |
| [`cauldron_2d_net`](https://hexdocs.pm/cauldron_2d_net) | the browser: a Phoenix channel, the pages, `cauldron.js`, and links to served worlds |
| [`cauldron_2d_wx`](https://hexdocs.pm/cauldron_2d_wx) | the desktop: a wx window drawing the same wire |
| [`linocut`](https://hexdocs.pm/linocut) | pictures as text or code, and pictures derived from others |
| [`cauldron_2d_easel`](https://hexdocs.pm/cauldron_2d_easel), [`_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter), [`_web`](https://hexdocs.pm/cauldron_2d_easel_web), [`_kino`](https://hexdocs.pm/cauldron_2d_easel_kino) | the atlas editors: in the terminal, in a browser, in Livebook |

## What is in the engine

| | |
|---|---|
| `Cauldron2D.Atlas` | the catalogue: a sprite (or frames at a rate), a glyph and a colour per tile, built in code or loaded from a directory of `.png` and `.pic` files; `subscribe/1` tells of a change |
| `Cauldron2D.Sheet` | the atlas packed onto one raster with an index, for a browser or a window |
| `Cauldron2D.Surface` | a grid of cells composited into one raster, without touching a pixel per frame; movers, animated frames at a time, and labels in `Linocut.Font` |
| `Cauldron2D.Camera` | which part of the world is on screen, and what is in each cell; `Camera.Follow` trails a target and shakes |
| `Cauldron2D.Loop` | a fixed timestep, so game speed does not follow frame rate |
| `Cauldron2D.Renderer` | pixels or glyphs, decided by the terminal |
| `Cauldron2D.Rng` | a seeded generator carried in state, so a game is reproducible |
| `Cauldron2D.Body` | a point mass with a heading: thrust, drag, gravity fields, wrapping |
| `Cauldron2D.Collision` | swept bodies against a grid of whole and half tiles, and each other |
| `Cauldron2D.Particles` | short-lived movers under a cap |
| `Cauldron2D.Map` | a tile map as text, picture or classic header format, with a game-supplied legend |
| `Cauldron2D.Input` | held actions from key presses and releases, with tap and toggle fallbacks |
| `Cauldron2D.World` | a `Cauldron2D.Game` run at a fixed tick for many players, each sent their own view; `stats/1` says how it keeps up |
| `Cauldron2D.World.Presence`, `Cauldron2D.World.Events` | joins and leaves in every world, and a world's events each tick, for processes that are not players |
| `Cauldron2D.Replay` | a record of joins and input that rebuilds the same game; `Replay.Viewer` plays it back to a watcher |
| `Cauldron2D.Audio` | effects placed around a listener, and music in sections and layers, per player |
| `Cauldron2D.Client.Game` | what a game gives every front end — terminal, browser, window — to put its worlds in front of a player; `Client.Hud` is the hud's data |
| `Cauldron2D.Arenas` | the arenas a game offers: a world each with its children, started on first use and swept when idle; `Stats` says how the node keeps up |
| `Cauldron2D.Robot` | a computer player: a process that joins as `{:robot, n}` and decides through a brain module on a cadence set by its skill |
| `Cauldron2D.Grid.Path`, `Cauldron2D.Grid.Coarse`, `Cauldron2D.Grid.Fov` | ways across a grid, in blocks, and what can be seen |
| `Cauldron2D.Minimap` | the whole map in a few rows of braille with marks |
| `Cauldron2D.Ledger`, `Cauldron2D.Save`, `Cauldron2D.Paths` | results and boards, saved games, and where a game's files live |
| `Cauldron2D.Beacon` | a server found on the local network |
| `Cauldron2D.Test` | a game driven in a test with no world and no clock |
| `Cauldron2D.Tuning`, `Cauldron2D.Trace` | the numbers a game plays by, and a trace `mix cauldron.report` reads |

Putting it on screen is [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter),
a separate package: nothing here depends on a UI framework, so a frame can be composed
and asserted on as bytes with no terminal, no app loop and no timing involved.

## How it fits together

A game is two modules. `Cauldron2D.Game` is the game itself — `init/1`, `join/3`,
`leave/2`, `handle_input/3`, `step/2`, `view/2`, `drain_events/1`, all pure — and
`Cauldron2D.World` runs it: players join from their own processes with
`Cauldron2D.Player`, send what they hold, and receive `{:cauldron_frame, %{tick, view,
events}}` every tick. Started with `record: true` the world keeps a `Cauldron2D.Replay`;
with `tick: :on_input` it steps only when input arrives, which is the world for a
turn-based game; `pause/1` and `resume/1` hold a clocked one; `state:` starts it from a
saved game.

`Cauldron2D.Client.Game` is what the front ends need to show it — its title, atlas,
actions and keymaps, arenas, how a view becomes a scene and a hud, its sounds and music
— and `cauldron_2d_drafter`, `cauldron_2d_net` and `cauldron_2d_wx` each put it in
front of a player with a title, a lobby, settings, the arena, a summary and the guide.
An arena whose world is `{module, opts}` is the player's own, started by the client. The
lobby lists the arenas; a game with only one and `lobby?: false` goes from its title
straight into it. Neither has anything to do with how a world steps: a turn-based game
whose players share a world has a lobby like any other, and what a player is in that
world — a character, a party — is the game's to ask, through its join props or a page of
its own.

`Cauldron2D.Audio` is one process per listener. Events carry a position and are scaled
and panned by their distance from the listener. `Cauldron2D.Audio.Music` plays a piece
the game declares as sections and layers — the engine names none of them — switching
sections on bar boundaries with a cross-fade and layer gains at once.

## Design notes

### The engine draws; the game is the game

Entities, combat, generation, turn order and saving belong to the game. The engine's
job is narrower: a grid of tile ids becomes bytes on a display, cheaply, on whatever
protocol is there. The one place they meet is a function:

```elixir
Cauldron2D.Camera.view(
  focus: {x, y},
  bounds: {width, height},
  size: {columns, rows},
  cell: fn {x, y} -> cell end
)
```

A roguelike's `cell` consults its map, entities and field of view; a brick game's
consults a map of bricks. Neither tells the engine anything else about itself.

### The fast path

Drawing every tile into a shared raster would be about 245,000 map writes a frame at 16 px
tiles and a 40×24 viewport. `Cauldron2D.Surface` touches no pixel on the frame path:

* **a tile is composited once.** A cell's appearance is fully described by
  `{base, overlays, tint}`; each distinct combination is alpha-blended once into a flat RGBA
  binary and cached in ETS. A few hundred cover a whole game
* **a frame is built by slicing.** Pixel row *n* of a row of tiles is `binary_part/3` of each
  tile at the same offset, concatenated — sub-binaries, no copying, no arithmetic per pixel

A 40×24 viewport is ~15,000 `binary_part` calls, about **1 ms**, and the result goes straight
into `FrenchCurve.Raster.from_rgba/4`.

**Movers** — sprites at fractional positions, for anything that is not on the grid — are a
separate path that touches only the rows they land on. Measured on a full playfield: 565 µs for
the grid, 609 µs with four movers on top.

### Two cells per tile

A tile is two terminal cells wide and one tall. Cells are about twice as tall as they are wide,
so a square tile drawn across two of them stays square — and the image's aspect ratio then
matches the cell box the terminal scales it into, which keeps the art from being stretched by
the terminal.

### Text mode

Terminals with no pixel protocol get two-cell coloured glyphs, from the same cells, so the two
renderings cannot disagree. Braille is not used for tiles: it packs 2×4 dots into a cell, so a
16-pixel tile would land on four dots and a monster would look like a wall.

Sub-tile positions have no text equivalent — a mover lands in the cell it is nearest to. A
game that needs the fraction to be visible needs pixels.

### Music

A layer written as a Strudel chain is performed live on the listener's stage, the
section's chains stacked, so a cue sounds at the next bar with nothing rendered ahead. The
player's music level is the pattern's master gain on the stage, so a change reaches notes
already sounding. A layer given as a score, a function or PCM (`{:pcm, binary}`) is rendered once and cached
instead, two stems at a time, the cued section first.

## Built with it

* **Scriber** — a turn-based roguelike with a console inside it
* **Carom** — a real-time Arkanoid
* **ExPilot** — a multiplayer XPilot over ssh, in a browser and in a window

## License

MIT
