# Installation

A Cauldron game needs two things: an engine, which is this package, and something that
puts the game in front of a player. `cauldron_core` is never added on its own in
practice — a drawing package or a front end brings it with it.

## Pick a target

| You want | Add | Start it with |
| --- | --- | --- |
| A terminal | `cauldron_2d_drafter` | `Cauldron2D.Drafter.Play.run/3` |
| A terminal over SSH or telnet | `cauldron_2d_drafter` | `Cauldron2D.Drafter.Server.start/1`, or `start_telnet/2` |
| A browser | `cauldron_2d_net` | `Cauldron2D.Net.Serve.run/3` |
| A desktop window | `cauldron_2d_wx` | `Cauldron2D.Wx.Client.run/1` |
| A phone or tablet | `cauldron_2d_native` and `cauldron_native` | `mix cauldron_native.build` |

Every row also gives you `cauldron_2d`, which draws the game, and `cauldron_core`, which
runs it. A game that draws its own pictures and only wants the engine can depend on
`cauldron_core` directly, but then it has no front end to play in.

## A terminal

```elixir
def deps do
  [
    {:cauldron_2d_drafter, "~> 0.4"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

Write the game's client module, then a mix task for it:

```elixir
defmodule Mix.Tasks.MyGame do
  use Mix.Task

  def run(argv), do: Cauldron2D.Drafter.Play.run(MyGame.Client, argv, name: "player")
end
```

`mix my_game --name alice` starts the application, opens the client and returns when the
player quits. Without a task of its own, `mix cauldron.play MyGame.Client` does the same.
`--mute` starts with sound off, `--picture` chooses how the terminal is drawn, and
`--trace FILE` writes the tracer's events.

`cauldron_2d_drafter` brings drafter and the `gamepad` package. Add
`tuning_fork_speaker` to hear sound on the machine the game runs on; without it the
audio stage stays silent and the game runs exactly the same. Add `cauldron_gpu` as well
if the game draws on the graphics card.

## SSH and telnet

The same package serves the same client over SSH, with accounts, an optional web
endpoint and a beacon on the local network:

```elixir
{:ok, server} = Cauldron2D.Drafter.Server.start(game: MyGame.Client, port: 2222)
```

`server.port` is the port actually served on. The worlds are the game's, registered with
[`Cauldron.Worlds`](worlds-and-players.html) before or after the server starts. Each
account gets its own sound port, which the terminal client sends PCM to through the
player's own tunnel; `stop/1` closes what `start/1` opened.

For a quick game with no accounts and no sound,
`Cauldron2D.Drafter.Server.start_telnet/2` listens on a port and runs the terminal
client for every connection.

## A browser

```elixir
def deps do
  [
    {:cauldron_2d_net, "~> 0.4"}
  ]
end
```

It brings Phoenix, Bandit, Mint, a WebSocket client, a PubSub and `cauldron_net`.

```elixir
defmodule Mix.Tasks.MyGame.Serve do
  use Mix.Task

  def run(argv), do: Cauldron2D.Net.Serve.run(MyGame.Client, argv, port: 4300)
end
```

`mix my_game.serve` serves the pages at `/play` and the player socket at `/socket`.
`--port` changes the port and `--drawing server|client|split` decides whether the server
or the browser draws. A game with its own endpoint mounts
`Cauldron2D.Net.Pages` and the socket in its router instead; the front end's README has
that shape. `:before` is a function run once the application has started, the place to
register the game's worlds.

## A desktop window

```elixir
def deps do
  [
    {:cauldron_2d_wx, "~> 0.4"}
  ]
end
```

```elixir
defmodule Mix.Tasks.MyGame.Desktop do
  use Mix.Task

  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")

    Cauldron2D.Wx.Client.run(
      game: MyGame.Client,
      username: Keyword.get(opts, :name, "player")
    )
  end
end
```

`Cauldron2D.Wx.Client.run/1` opens the window and returns when it is closed. It needs an
Erlang built with `wx`; the drawing is `cauldron_2d`'s, so the game looks as it does in
the terminal. To play on a server instead of in the same node, `:link` is a function that
takes a world and returns the socket or node link to join with.

## A phone or a tablet

```elixir
def deps do
  [
    {:cauldron_2d_native, "~> 0.1", targets: [:ios, :android]},
    {:cauldron_native, "~> 0.1", runtime: Mix.target() in [:ios, :android]}
  ]
end
```

```elixir
# config/config.exs
if config_target() in [:ios, :android] do
  config :cauldron_2d_native, game: MyGame.Client
end
```

```
mix cauldron_native.build ios --team ABCDE12345 --run
mix cauldron_native.build android --run
```

`cauldron_native` embeds the release, draws the screen and reads touch; `cauldron_2d_native`
is what runs inside it. The phone shows the game's own title and summary and its worlds;
it has no text screens for a lobby, settings or a guide, so a game reaches its options
through its own menu. The
[Mobile releases guide](https://hexdocs.pm/cauldron_native/building_apps.html) covers
signing and building.

## Requirements

`cauldron_core` declares `elixir: "~> 1.18"`. The sound packages it depends on declare
`~> 1.19` today, so a project that plays sound should run Elixir 1.19 or later; a project
that pins older sound packages can stay on 1.18. No OTP version is pinned in the source:
the floor is whatever the Elixir release you use needs.

What else your machine needs comes from the pieces you add:

| Piece | Needs |
| --- | --- |
| Speaker output | `tuning_fork_speaker`: a C compiler, and the ALSA headers (`libasound2-dev`) on Linux |
| Desktop window | an Erlang built with `wx` |
| SSH server | Erlang's `:ssh` application, which the server starts itself |
| Phone build | iOS or Android toolchains, as `cauldron_native` documents |
| Records and boards | no build tools: `Cauldron.Save`, `Cauldron.Scores` and `Cauldron.Ledger` use `:erlang`, `:dets` and, for the ledger's lock, the system's process list |

## What each dependency is for

| Package | Holds |
| --- | --- |
| `cauldron_core` | Worlds, players, input, menus, the shared client modules, sound, saving, scores, networking, testing |
| `cauldron_2d` | Tiles, atlases, pictures, 2D drawing, projections |
| `cauldron_2d_drafter` | The terminal front end and its SSH server; brings `drafter` and `gamepad` |
| `cauldron_net` | Worlds on the network: sessions, socket links, node links |
| `cauldron_2d_net` | The browser front end: pages, channel, drawer; brings Phoenix and Bandit |
| `cauldron_2d_wx` | The desktop window front end |
| `cauldron_2d_native`, `cauldron_native` | The phone front end, and the iOS and Android host |
| `tuning_fork` | Audio synthesis, patterns, score rendering and the audio sinks |
| `tuning_fork_speaker` | The sink that plays through this machine's speaker |
| `gamepad` | Game-controller events, as `Cauldron.Input.Pad` reads them |
| `cauldron_gpu` | Metal and Vulkan rendering, optional to every front end |

`cauldron_core` depends on `tuning_fork`; sound is silent, not absent, without
`tuning_fork_speaker`.

## Configuration

```elixir
config :cauldron_core, sweeper: [idle_after: 120, every: 30]
config :cauldron_core, beacon_port: 2299
```

`:sweeper` says how long a world with no human in it runs before
`Cauldron.Worlds.Sweeper` stops it, and how often the sweeper looks. `:beacon_port` is
the UDP port `Cauldron.Beacon` calls on.

## Where to go next

| You want to | Read |
| --- | --- |
| Understand worlds, players and ticks | [Worlds and players](worlds-and-players.html) |
| Take input and show menus | [Input and menus](input-and-menus.html) |
| Play sound and music | [Sound and music](sound-and-music.html) |
| Keep scores, settings and saves | [Saving and scores](saving-and-scores.html) |
| Test a game with no process | [Testing](testing.html) |
| Draw the game | [`cauldron_2d`'s tutorial](https://hexdocs.pm/cauldron_2d/tutorial.html) |
| Find a word | [Glossary](glossary.html) |
