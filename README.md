# Cauldron

A game engine for the BEAM, terminal first, with the browser and the desktop as further
front ends. This repository holds the engine and the packages around it, each an ordinary
Mix project in its own directory.

| Package | What |
| --- | --- |
| [`cauldron_2d`](cauldron_2d) | The 2D engine: tiles, sprites, camera, physics, collision, input, worlds, players, replay, audio. No terminal, no UI framework |
| [`cauldron_2d_drafter`](cauldron_2d_drafter) | The terminal: a surface widget and a ready-made client on [drafter](https://hexdocs.pm/drafter) |
| [`cauldron_2d_net`](cauldron_2d_net) | The network: the wire and the sprite sheet, the served side (a Phoenix channel, socket and API, the sound policy), the browser client `cauldron.js`, the links an Elixir client uses to join a world over the socket or on a connected node, the remote calls, the load test |
| [`cauldron_2d_wx`](cauldron_2d_wx) | The desktop: a wx window drawing the same wire |
| [`linocut`](linocut) | Pictures written as code or loaded from files, and the derivations a game needs — including a picture derived from another by a line: recolour by key, flip, turn, shift, a frame, a picture laid over |
| [`cauldron_2d_easel`](cauldron_2d_easel) | Editing an atlas as data: pictures, palettes, frames, undo; an art directory with its manifest |
| [`cauldron_2d_easel_drafter`](cauldron_2d_easel_drafter) | The atlas editor in the terminal (`mix cauldron.easel`), with the picture at actual size through the terminal's graphics |
| [`cauldron_2d_easel_web`](cauldron_2d_easel_web) | The atlas editor in a browser, with LiveView |
| [`cauldron_2d_easel_kino`](cauldron_2d_easel_kino) | The atlas editor as a Livebook cell; pictures, sheets and animations as images |
| [`examples/cistern`](examples/cistern) | The tutorial's game: every package above in one small project, with tests |

Start with [Your first game](cauldron_2d/guides/tutorial.md), which builds
[`examples/cistern`](examples/cistern) step by step — the game as a value, its tests, its
art, the terminal, sound, more players, the browser and the window — then
[`cauldron_2d/README.md`](cauldron_2d/README.md) for the engine's parts and design.
Each package's documentation is on [hexdocs.pm](https://hexdocs.pm/cauldron_2d).
To draw before reading, the art notebook opens straight into Livebook — the editor in a
cell, a picture as text and as code, an animation, a directory installed as an atlas:

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjaman%2Fcauldron%2Fmain%2Fcauldron_2d_easel_kino%2Fnotebooks%2Feasel.livemd)

`GAP_ANALYSIS.md` is what the stack was found to be missing on 2026-09-17 and `STATE.md`
is what has been done about it.

## Working from this repository

Within the repository the packages depend on each other by path, so an edit in
`cauldron_2d` is seen by the others at once. `drafter`, `french_curve` and `tuning_fork`
are path dependencies one level up. `mix test`, `mix credo --strict` and `mix format
--check-formatted` run inside each package and pass.

## Built with it

* ExPilot — multiplayer XPilot over ssh, in a browser and in a window
* Carom — real-time Arkanoid, on `Cauldron2D.Drafter.Client` from an arena of the player's own
* Scriber — turn-based roguelike, in a `Cauldron2D.World` stepped on input

## License

MIT
