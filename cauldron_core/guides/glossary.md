# Glossary

The words Cauldron uses, in alphabetical order. Each is the engine's, not a particular
game's: a game invents its actions, its sections and its own nouns, and keeps these for
the parts every game shares.

Where a word belongs to a package other than this one, the link goes there.

## Actions

The atoms a game invents for what a player can do, which a keymap binds to keys, mouse
buttons and controller controls. Read [Input and menus](input-and-menus.html).

## Arena

The older word for a world, accepted where a ledger row or a recorder is labelled with
the place a result came from. Read [Worlds and players](worlds-and-players.html).

## Atlas

The game's collection of pictures and glyphs, installed once and named by a scene's cell
and mover entries. Read [`cauldron_2d`'s tutorial](https://hexdocs.pm/cauldron_2d/tutorial.html).

## Beacon

The UDP call a host makes every two seconds so players on the local network can find it,
on the port set by `config :cauldron_core, beacon_port: n`. Read
[Installation](installation.html#configuration).

## Client

The module implementing `Cauldron.Client.Game` that tells every front end what the game
is called, how it is drawn, and what its actions, worlds, sounds and menus are. Read
[Introduction](introduction.html).

## Drain events

The world's one call of the game's `drain_events/1` after a step, whose list goes to
every player's frame and to every subscriber. Read
[Worlds and players](worlds-and-players.html).

## Drawer

What a networked session sends a scene to, so a browser, a window or a server can draw
it. Read the [`cauldron_net` README](https://hexdocs.pm/cauldron_net/readme.html).

## Front end

The package that runs the screens a player sees — the terminal, the browser, the window,
the phone — all of which take the same client module. Read
[Installation](installation.html).

## Hud

The rows a client draws beside or under the world, given as text runs by the game's
`hud/1`. Read [Introduction](introduction.html).

## Ledger

The DETS-backed record of every player's results on a node, and the boards it computes
from them. Read [Saving and scores](saving-and-scores.html).

## Link

One TCP connection between two worlds playing with rollback on different machines,
carrying only what they must tell each other. Read
[Worlds and players](worlds-and-players.html).

## Party

A client's player, its seats, and the routing of its controllers, held together while it
plays in a world. Read [Input and menus](input-and-menus.html).

## Presses

The value a game keeps with a player to tell what was pressed and released since the last
step. It remembers a press for a moment after it happened. Read
[Input and menus](input-and-menus.html).

## Replay

The record of joins, leaves and input a world kept with `record: true`, enough to run the
same game to the same state again. Read [Worlds and players](worlds-and-players.html).

## Scene

The map a client draws, built from a view by the game's client module, whose keys are the
drawing package's. Read [Introduction](introduction.html).

## Seats

The further players a client plays on one machine, each with its own keys and controller,
joined as `"<username> 2"` and on with frames off. Read
[Input and menus](input-and-menus.html).

## Sweeper

The process that stops worlds with no human in them for a while, so an idle server does
not keep every world running. Read [Worlds and players](worlds-and-players.html).

## Tick

One turn of a world's loop: it applies waiting input, runs the steps that have come due,
drains events, and sends the frames that are due. Read
[Worlds and players](worlds-and-players.html).

## View

Whatever a game's `view/2` returns for one player, which is that player's alone and is
sent to them in a frame. Read [Worlds and players](worlds-and-players.html).

## World

The process that runs one game at a fixed tick and keeps its players supplied with views.
Read [Worlds and players](worlds-and-players.html).

## Words by guide

| Guide | Words |
| --- | --- |
| [Installation](installation.html) | Front end, beacon |
| [Worlds and players](worlds-and-players.html) | World, arena, tick, view, drain events, sweeper, link, replay |
| [Input and menus](input-and-menus.html) | Actions, presses, seats, party |
| [Sound and music](sound-and-music.html) | — |
| [Saving and scores](saving-and-scores.html) | Ledger |
| [Testing](testing.html) | — |
| [Troubleshooting](troubleshooting.html) | — |
| [Introduction](introduction.html) | Client, scene, hud |
| [`cauldron_2d`'s tutorial](https://hexdocs.pm/cauldron_2d/tutorial.html) | Atlas |
| [`cauldron_net` README](https://hexdocs.pm/cauldron_net/readme.html) | Drawer |

## Words a game invents

Everything else is the game's. A game names its actions, its worlds, its sections and
layers, its metrics, its saves and its players. The engine reads those names but never
interprets them. Two games can therefore use the same words for different things, and
neither has to explain itself to Cauldron.
