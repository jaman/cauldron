# Cauldron

Cauldron is a family of Elixir packages for writing games on the BEAM. You write the game
once as plain data and pure functions. Cauldron runs it for one player or many, and puts
it on screen in a terminal, a browser or a desktop window. Each package is an ordinary
Mix project in its own directory of this repository.

## What a Cauldron game is

A Cauldron game is two modules.

* **The world module** implements `Cauldron2D.Game`. It holds the game's state and changes
  it. Its callbacks are `init/1`, `join/3`, `leave/2`, `handle_input/3`, `step/2`,
  `view/2` and `drain_events/1`. Every one of them is pure: none reads a clock or draws.
  `Cauldron2D.World` runs this module at a fixed tick and sends each player their own
  view every tick. A turn-based game starts its world with `tick: :on_input`, so the world
  steps only when input arrives.
* **The client module** implements `Cauldron2D.Client.Game`. It tells every front end how
  to show the game. It names the title, the atlas of pictures, the actions and the keys
  that press them, and the worlds a player can join. It turns a view into a scene and a
  hud. It also gives the game's sounds and music.

A front end takes the client module and runs the screens a player sees: the title, the
lobby, the settings, the world, the summary when play is over, and the guide. The same
client module works with every front end.

Because the world module is pure, you can test it with no process and no clock.
`Cauldron2D.Test` joins players, holds actions, runs ticks and reads views and events.

## Where a game can be played

| Target | Package | How you start it |
| --- | --- | --- |
| A terminal | [`cauldron_2d_drafter`](cauldron_2d_drafter) | `Drafter.run(Cauldron2D.Drafter.Client, props: %{game: MyGame.Client})` |
| A terminal over ssh | [`cauldron_2d_drafter`](cauldron_2d_drafter) | `Cauldron2D.Drafter.Server.start(game: MyGame.Client, port: 2222)` serves accounts, sound and a beacon. `Drafter.Server.start_ssh/2` and `start_telnet/2` serve `Cauldron2D.Drafter.Client` without them |
| A browser | [`cauldron_2d_net`](cauldron_2d_net) | Forward a path to `Cauldron2D.Net.Pages`. Add a socket that uses `Cauldron2D.Net.Socket` and a channel that uses `Cauldron2D.Net.Channel` |
| A desktop window | [`cauldron_2d_wx`](cauldron_2d_wx) | `Cauldron2D.Wx.Client.run(game: MyGame.Client, username: "alice")` |
| The graphics card, in the terminal pane or its own window | [`cauldron_gpu`](cauldron_gpu) with [`cauldron_2d_drafter`](cauldron_2d_drafter) | Give the scene a `:gpu` function. The terminal client then draws on the card when there is one. The player's Drawing setting, or the picture options `software`, `gpu` and `window`, change that |
| 3D in a browser | [`cauldron_3d_net`](cauldron_3d_net) | Open a `Cauldron3D.Net.Scene` and serve `Cauldron3D.Net.Page`. three.js draws it |

The terminal client draws pixels when the terminal has an image protocol. Otherwise it
draws coloured glyphs from the same atlas. A game whose scene draws its own picture can
choose how that picture reaches the terminal. Set the picture options with the `:picture`
mount prop, the `CAULDRON_PICTURE` environment variable, or the game's `look/0`. The
options are `native`, `native:N`, `size:WxH`, `png`, `swap`, `gpu`, `window`, `software` and
`none`. `Cauldron2D.Drafter.Client.Picture` describes each one.

A game that needs files or choices before it runs can show `Cauldron2D.Drafter.Launcher`
first. It is a setup page for paths, skill and drawing. It saves the player's choices, so
later runs start straight away.

## The other pieces

**Sound and music.** `Cauldron2D.Audio` plays a game's events as sound. It runs on
[`tuning_fork`](https://hexdocs.pm/tuning_fork). An event placed at `{x, y}` is quieter
and panned the farther it is from the listener. Music is pieces in sections and layers,
played by `Cauldron2D.Audio.Music`. Your client module's `sounds/0`, `music/0` and `cue/2`
provide them. Add `tuning_fork_speaker` to your deps to hear sound on the local machine.

**Pictures and art.**

* `Cauldron2D.Atlas` holds a game's pictures. Build an atlas in code with `Atlas.new/2`
  and `Atlas.put/4`, or load a directory of `.png` and `.pic` files with `Atlas.load/3`.
* [`linocut`](linocut) writes pictures as code (`Linocut.sprite/3`) and reads `.pic`
  files. It derives one picture from another with a line, such as a recolour or a flip.
  `Linocut.Font` draws text onto a picture with a small pixel font.
* The easel packages edit an art directory. [`cauldron_2d_easel`](cauldron_2d_easel)
  is the editing as data. [`cauldron_2d_easel_drafter`](cauldron_2d_easel_drafter) is the
  editor in a terminal (`mix cauldron.easel`). [`cauldron_2d_easel_web`](cauldron_2d_easel_web)
  is the editor in a browser. [`cauldron_2d_easel_kino`](cauldron_2d_easel_kino) is the
  editor in a Livebook cell.
* [`cauldron_2d_gamemaker`](cauldron_2d_gamemaker) reads the data file of a GameMaker game
  you own, and can run that game.

**3D.**

* [`cauldron_3d`](cauldron_3d) is a 3D engine in pure Elixir. It draws polygons, meshes,
  billboards and BSP worlds into indexed-colour frames.
* [`cauldron_3d_formats`](cauldron_3d_formats) reads the Quake family of files into
  `cauldron_3d`: paks, maps, models, sprites, textures and sounds.
* [`quake_c`](quake_c) is a QuakeC virtual machine. It runs compiled QuakeC programs
  against builtins you supply.
* [`cauldron_gpu`](cauldron_gpu) draws 3D scenes on the graphics card with Metal or Vulkan.
* [`cauldron_3d_net`](cauldron_3d_net) sends a `cauldron_gpu` scene to browsers.

## Your first game

This section builds a small game called Gather. You walk a figure around a field and pick
up coins. It uses `cauldron_2d`, `cauldron_2d_drafter` and `linocut`.

### 1. Add the dependencies

```elixir
def deps do
  [
    {:cauldron_2d, "~> 0.2"},
    {:cauldron_2d_drafter, "~> 0.2"},
    {:linocut, "~> 0.2"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

### 2. Write the world module

The state is a map. `step/2` moves each player by the actions they hold. When a player
reaches the coin, the score goes up, the coin moves, and a `{:coin, {x, y}}` event is
recorded. `Cauldron2D.Rng` keeps the random numbers in the state, so the same seed plays
the same game.

```elixir
defmodule Gather.Game do
  @behaviour Cauldron2D.Game

  alias Cauldron2D.Rng

  @size {16, 10}
  @speed 6.0

  @impl true
  def init(opts) do
    %{players: %{}, coin: {8, 5}, rng: Rng.new(Keyword.get(opts, :seed, 1)), events: []}
  end

  @impl true
  def join(game, id, props) do
    player = %{name: Map.get(props, :username, "player"), pos: {1.0, 1.0}, held: MapSet.new(), score: 0}
    {:ok, put_in(game, [:players, id], player)}
  end

  @impl true
  def leave(game, id), do: %{game | players: Map.delete(game.players, id)}

  @impl true
  def handle_input(game, id, %{held: held}) do
    case game.players do
      %{^id => _player} -> put_in(game, [:players, id, :held], held)
      _absent -> game
    end
  end

  @impl true
  def step(game, dt) do
    Enum.reduce(game.players, game, fn {id, player}, acc -> move(acc, id, player, dt) end)
  end

  @impl true
  def view(game, id) do
    %{me: game.players[id], players: Map.values(game.players), coin: game.coin, size: @size}
  end

  @impl true
  def drain_events(game), do: {Enum.reverse(game.events), %{game | events: []}}

  defp move(game, id, player, dt) do
    {x, y} = player.pos
    {width, height} = @size
    across = pressed(player.held, :right) - pressed(player.held, :left)
    down = pressed(player.held, :down) - pressed(player.held, :up)
    pos = {clamp(x + across * @speed * dt, width - 1), clamp(y + down * @speed * dt, height - 1)}

    game
    |> put_in([:players, id, :pos], pos)
    |> collect(id, pos)
  end

  defp collect(%{coin: {coin_x, coin_y}} = game, id, {x, y})
       when round(x) == coin_x and round(y) == coin_y do
    {width, height} = @size
    {next_x, rng} = Rng.roll(game.rng, width)
    {next_y, rng} = Rng.roll(rng, height)

    game
    |> update_in([:players, id, :score], &(&1 + 1))
    |> Map.merge(%{coin: {next_x - 1, next_y - 1}, rng: rng, events: [{:coin, {coin_x, coin_y}} | game.events]})
  end

  defp collect(game, _id, _pos), do: game

  defp pressed(held, action), do: if(MapSet.member?(held, action), do: 1, else: 0)

  defp clamp(value, top), do: value |> max(0.0) |> min(top / 1)
end
```

### 3. Test it without a world

```elixir
driver = Cauldron2D.Test.new(Gather.Game, hz: 30)
{:ok, driver} = Cauldron2D.Test.join(driver, :alice, %{username: "alice"})
driver = driver |> Cauldron2D.Test.hold(:alice, [:right, :down]) |> Cauldron2D.Test.tick(40)
Cauldron2D.Test.view(driver, :alice).me.pos
#=> {9.0, 9.0}
```

### 4. Write the client module

The atlas has three pictures, drawn with `Linocut.sprite/3`. A tile here is 8 pixels
square. Each picture also has a glyph and a colour for terminals without images.

`scene/1` describes what to draw. `cell` gives each tile as `{base, overlays, tint}`, so
the coin is an overlay on the grass. `movers` are pictures at any position, so the
players move smoothly between tiles. The one world in `worlds/1` is
`{Gather.Game, [hz: 30]}`. The client starts that world for the player when they join it.

```elixir
defmodule Gather.Client do
  @behaviour Cauldron2D.Client.Game

  alias Cauldron2D.Atlas

  @impl true
  def title, do: %{name: "GATHER", tagline: "pick up the coins"}

  @impl true
  def atlas do
    if Atlas.installed?(:gather), do: :gather, else: install_atlas()
  end

  defp install_atlas do
    Atlas.new(:gather, tile: 8)
    |> Atlas.put(:grass, Linocut.sprite(String.duplicate("GGGGGGGG\n", 8), G: "#2e6b34"),
      glyph: ". ",
      color: {70, 140, 80}
    )
    |> Atlas.put(:coin, Linocut.sprite("..YY..\n.YYYY.\n.YYYY.\n..YY..", Y: "#ffd040"),
      glyph: "()",
      color: {255, 208, 64}
    )
    |> Atlas.put(:hero, Linocut.sprite(".BB.\nBBBB\n.BB.\nB..B", B: "#6cb8ff"),
      glyph: "@ ",
      color: {108, 184, 255}
    )
    |> Atlas.install()
  end

  @impl true
  def actions, do: [:left, :right, :up, :down]

  @impl true
  def keymaps do
    [
      arrows: %{left: [:left], right: [:right], up: [:up], down: [:down]},
      wasd: %{left: [:a], right: [:d], up: [:w], down: [:s]}
    ]
  end

  @impl true
  def toggles, do: []

  @impl true
  def worlds(_props) do
    [%{id: :field, name: "A field of your own", world: {Gather.Game, [hz: 30]}, players: 0, humans: []}]
  end

  @impl true
  def scene(view) do
    {width, height} = view.size

    %{
      focus: {width / 2, height / 2},
      bounds: view.size,
      cell: fn point -> if point == view.coin, do: {:grass, [:coin], nil}, else: {:grass, [], nil} end,
      movers: Enum.map(view.players, &{:hero, &1.pos})
    }
  end

  @impl true
  def hud(%{me: nil}), do: [["watching"]]
  def hud(%{me: me}), do: [[{"coins #{me.score}", {255, 208, 64}}]]

  @impl true
  def listener(%{me: nil}), do: nil
  def listener(%{me: me}), do: me.pos

  @impl true
  def sounds, do: &voice/1

  @impl true
  def music, do: []

  @impl true
  def cue(_view, _screen), do: nil

  defp voice(:coin) do
    TuningFork.Voice.new(shape: :sine, freq: 880.0, envelope: TuningFork.Envelope.hit(0.15), gain: 0.3)
  end

  defp voice(_event), do: nil
end
```

### 5. Run it in the terminal

Register the surface widget with drafter, then run the terminal client with your client
module. A mix task is a convenient place for this:

```elixir
defmodule Mix.Tasks.Gather do
  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    Drafter.run(Cauldron2D.Drafter.Client, props: %{game: Gather.Client, username: "alice"})
  end
end
```

Run `mix gather`. Press `Enter` on the title to reach the lobby, and `Enter` again to join
your field. Move with the arrows or WASD. Press `Esc` to go back a screen.

### Where to go next

* [Your first game](cauldron_2d/guides/tutorial.md) builds
  [`examples/cistern`](examples/cistern) step by step. It adds art from `.pic` files,
  settings, music, shared worlds, a robot player, the browser and the window.
* To serve the same game in a browser, see [`cauldron_2d_net`](cauldron_2d_net/README.md).
* To open it in a window, see [`cauldron_2d_wx`](cauldron_2d_wx/README.md).
* To serve it over ssh, see [`cauldron_2d_drafter`](cauldron_2d_drafter/README.md).
* For the engine's modules (camera, collision, maps, projections, robots, replay), see
  [`cauldron_2d`](cauldron_2d/README.md).

To draw before you code, open the art notebook in Livebook. It has the editor in a cell, a
picture as text and as code, an animation, and a directory installed as an atlas:

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjaman%2Fcauldron%2Fmain%2Fcauldron_2d_easel_kino%2Fnotebooks%2Feasel.livemd)

## Packages

| Package | What it does |
| --- | --- |
| [`cauldron_2d`](cauldron_2d) | The 2D engine. It has tiles, sprites, the camera, physics, collision, input, worlds, players, replay and audio. It has no terminal or UI code |
| [`cauldron_2d_drafter`](cauldron_2d_drafter) | Plays a game in a terminal, on [drafter](https://hexdocs.pm/drafter). It has a surface widget, a ready-made client and an ssh server |
| [`cauldron_2d_net`](cauldron_2d_net) | Plays a game in a browser. It has a Phoenix channel, socket, pages and API, and the browser script `cauldron.js`. Elixir clients use it to join a world on another machine |
| [`cauldron_2d_wx`](cauldron_2d_wx) | Plays a game in a desktop window, with wx |
| [`linocut`](linocut) | Writes pictures as code and loads them from files. It derives new pictures from old ones and draws text with a pixel font |
| [`cauldron_2d_easel`](cauldron_2d_easel) | Edits an atlas as data: pictures, palettes, frames and undo. It reads and writes an art directory with its manifest |
| [`cauldron_2d_easel_drafter`](cauldron_2d_easel_drafter) | The atlas editor in a terminal (`mix cauldron.easel`). It also has a sector map editor (`mix cauldron.sectors`) |
| [`cauldron_2d_easel_web`](cauldron_2d_easel_web) | The atlas editor in a browser, with LiveView |
| [`cauldron_2d_easel_kino`](cauldron_2d_easel_kino) | The atlas editor in a Livebook cell. It shows pictures, sheets and animations as images |
| [`cauldron_2d_gamemaker`](cauldron_2d_gamemaker) | Reads a GameMaker game's data file: sprites, texture pages, tilesets, objects, rooms, sounds, fonts and paths. It can also run the game |
| [`cauldron_3d`](cauldron_3d) | A 3D engine in pure Elixir. It has cameras, polygons, keyframed meshes, billboards, and BSP worlds with lightmaps and collision |
| [`cauldron_3d_formats`](cauldron_3d_formats) | Reads Quake and Half-Life files into `cauldron_3d`: paks, pk3s, maps, models, sprites, WADs, TGA, BMP and WAVE |
| [`quake_c`](quake_c) | A QuakeC virtual machine. It runs id's and FTE's compiled programs against the host's builtins |
| [`cauldron_gpu`](cauldron_gpu) | Draws 3D on the graphics card with Metal and Vulkan. It draws to a window or to offscreen frames for the terminal, and converts BSP worlds, models and Doom sector maps |
| [`cauldron_3d_net`](cauldron_3d_net) | Sends a `cauldron_gpu` scene to browsers over a Phoenix channel. A three.js client draws it |

## Examples

| Example | What it shows |
| --- | --- |
| [`examples/cistern`](examples/cistern) | The tutorial's game. It uses every 2D package and has tests |
| [`examples/town`](examples/town) | A town you walk top-down, isometric or in first person. It uses the engine's projections, standing art with doors, villagers and a game controller |
| [`examples/beast`](examples/beast) | A side-scroller with parallax layers. A runner crosses endless terrain while bats and crawlers attack |
| [`examples/megablast`](examples/megablast) | A vertical shooter with parallax. Waves of creatures fly in formation, with music from tuning_fork |
| [`examples/parade`](examples/parade) | A courtyard of knights. Spells are aimed and cast as areas, and `Cauldron2D.Route` finds paths |

## Working from this repository

Inside the repository the packages depend on each other by path. An edit in `cauldron_2d`
is seen by the others at once. `drafter`, `french_curve` and `tuning_fork` are path
dependencies one level up. Run `mix test`, `mix credo --strict` and
`mix format --check-formatted` inside each package. Each package's documentation is on
[hexdocs.pm](https://hexdocs.pm/cauldron_2d).

## Built with it

* ExPilot: multiplayer XPilot over ssh, in a browser and in a window.
* Carom: real-time Arkanoid on `Cauldron2D.Drafter.Client`.
* Scriber: a turn-based roguelike in a `Cauldron2D.World` stepped on input.
* ElixirDoom: Doom on the sector maps of `cauldron_2d`. It is its own GPL package.
* ElixirQuake: Quake on `cauldron_3d`, with its QuakeC run on `quake_c`. It is its own GPL package.
* ElixirHalfLife: Half-Life with FreeHL's QuakeC on `quake_c`. It is its own GPL package.

## License

MIT
