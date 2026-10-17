# Cauldron2D.Drafter

This package puts a [`cauldron_2d`](https://hexdocs.pm/cauldron_2d) game in a terminal,
through [drafter](https://hexdocs.pm/drafter). It also serves the game over ssh. It gives
you two things:

* **A ready-made client.** `Cauldron2D.Drafter.Client` is a whole drafter application. It
  runs any `Cauldron2D.Client.Game` module through a title, a lobby, settings, the world,
  a summary and a guide.
* **Parts for your own application.** Use these when your game has a different shape.
  * `Cauldron2D.Drafter.Surface` is the `cauldron_surface` widget. It draws a viewport onto
    a grid and its movers. It uses pixels where the terminal has them and glyphs elsewhere.
  * `Cauldron2D.Drafter.Sprites` sends an atlas to a kitty terminal once, so later frames
    only place the sprites.
  * `Cauldron2D.Drafter.Chat` keeps rooms of messages and sends each to its members.

The same `Cauldron2D.Client.Game` module also runs in a browser through
[`cauldron_2d_net`](https://hexdocs.pm/cauldron_2d_net) and in a window through
[`cauldron_2d_wx`](https://hexdocs.pm/cauldron_2d_wx).

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_drafter, "~> 0.3"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

This brings in `cauldron_2d`, drafter `~> 0.5` and the `gamepad` package for game
controllers. Add `tuning_fork_speaker` to hear sound on this machine. Add
[`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu) as well if your game draws on the
graphics card. It is an optional dependency here.

## Running a game in the terminal

Write a client module for your game. This one shows the `Walk.Game` from the
`cauldron_2d` README. It builds a two-tile atlas in code, lists one world of the player's
own, and starts straight in it:

```elixir
defmodule Walk.Client do
  @behaviour Cauldron2D.Client.Game

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @impl true
  def title, do: %{name: "Walk", tagline: "left and right"}

  @impl true
  def atlas do
    Atlas.new(:walk, tile: 8)
    |> Atlas.put(:floor, Raster.new(8, 8, background: {40, 44, 60, 255}), glyph: ". ", color: {90, 96, 120})
    |> Atlas.put(:walker, Raster.new(8, 8, background: {240, 200, 80, 255}), glyph: "@ ", color: {240, 200, 80})
    |> Atlas.install()
  end

  @impl true
  def actions, do: [:left, :right]

  @impl true
  def keymaps, do: [arrows: %{left: [:left], right: [:right]}]

  @impl true
  def toggles, do: []

  @impl true
  def worlds(_props),
    do: [%{id: :field, name: "A field of your own", world: {Walk.Game, [hz: 30]}}]

  @impl true
  def scene(%{me: me, width: width}) do
    %{
      focus: {width / 2, 0.5},
      bounds: {width, 1},
      cell: fn _tile -> {:floor, [], nil} end,
      movers: [{:walker, {me.x, 0.0}}]
    }
  end

  @impl true
  def hud(%{me: me}), do: [["x ", {Float.to_string(Float.round(me.x, 1)), {240, 200, 80}}]]

  @impl true
  def listener(%{me: me}), do: {me.x, 0.0}

  @impl true
  def sounds, do: fn _event -> nil end

  @impl true
  def music, do: []

  @impl true
  def cue(_view, _screen), do: nil

  @impl true
  def start, do: {:play, :first}
end
```

Then load and register the surface widget, and run the client with your module in its
props. A mix task is a good place for this:

```elixir
Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

Drafter.run(Cauldron2D.Drafter.Client, props: %{game: Walk.Client, username: "alice"})
```

Register the widget only after loading the module. Registration reads the module's
`component_tag/0`. An unloaded module registers nothing, and its tag then draws an empty
pane. The same holds for `Drafter.run/2`'s `:widget_libraries` option.

The examples in the repository's `examples` directory each have a mix task written this
way: `mix cistern`, `mix beast`, `mix town`, `mix parade`.

## The ready-made client

The client holds the player's `Cauldron2D.Input`, their `Cauldron2D.Audio` and their
connection to the `Cauldron2D.World`. The game supplies every name and element the
screens show. The client supplies the flow between screens and the keys that drive it.

* **Flow.** The game's `start/0`, or the `:start` mount prop, chooses where the client
  starts. `:lobby` shows the title, then the lobby. `{:lobby, title: false}` starts at the
  lobby. `{:play, id}` goes straight into a world. A function of the client's state runs
  a flow of the game's own, using `enter/3`, `to_lobby/1`, `to_title/1` and `to_guide/1`.
* **Lobby.** It lists the worlds from the game's `worlds/1` with their players, and
  redraws as players come and go. It offers teams where a world has them, and a chat
  unless the game's `chat?/0` returns `false`.
* **Keys.** `Esc` goes back, `q` leaves the world for the lobby, `?` shows the key hints and `^Q`
  quits. `=`, `-` and `0` zoom. `v` cycles the projections the game's `look/0` lists:
  top-down, oblique, isometric, mode 7 and first person. `[` and `]` turn the view. The
  game can replace or drop any of these with `client_keys/0`. `Cauldron2D.Drafter.Client`
  documents every key.
* **Controllers.** Each connected controller plays one player. The d-pad and left stick
  hold the game's directions. In a game's menu, the d-pad arrives as arrow keys, `A` as
  `Enter`, and `B` and `Start` as `Esc`, each sent as `{:key, key, [:pad]}`.
* **Guide.** A game with `guide/0` gets a guide screen on `h` from the title and lobby.
* **Settings.** The player sets the control preset and bindings, pointer steering,
  effects and music levels, the display and the frame rate. The client saves them under
  `$XDG_CONFIG_HOME/<game>/<player>.settings`, and in the player's account when there is
  one.
* **Sound.** Pass `mute: true` in the props, set `config :cauldron_2d_drafter, mute: true`,
  or set `CAULDRON_MUTE=1` to play no sound.

A game with screens of its own can run the client inside its own `Drafter.App`. Start it
with `start: {:lobby, title: false}` and hand it events through `handle_event/2`,
`handle_event/3`, `on_message/2` and `on_ready/1`. The Embedding section of
`Cauldron2D.Drafter.Client` lists the `use Drafter.App` options your app needs.

## Serving over ssh and telnet

`Cauldron2D.Drafter.Server.start/1` serves the game over ssh. It registers the surface
widget, keeps player accounts, gives each account a sound port, starts the game's web
endpoint if you give one, and announces the server on the local network:

```elixir
{:ok, server} =
  Cauldron2D.Drafter.Server.start(
    game: Walk.Client,
    port: 2222,
    web: {:my_game, MyGame.Web.Endpoint, 2280}
  )

Cauldron2D.Drafter.Server.stop(server)
```

New players register by logging in as `new@host`. Each player's sound goes as raw PCM
through an `ssh -R <port>:127.0.0.1:4713` tunnel to a player program on their machine.
Register the worlds with `Cauldron2D.Worlds` before or after the server starts.

To serve without accounts, call drafter's server directly. This serves the client over
telnet. Pass `mute: true`, because a telnet session has no sound tunnel:

```elixir
Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

Drafter.Server.start_telnet(Cauldron2D.Drafter.Client,
  port: 2323,
  mount_props: %{game: Walk.Client, mute: true}
)
```

`Drafter.Server.start_ssh/2` takes the same `mount_props`. See drafter's remote TUI guide
for its other options.

## The surface widget

```elixir
{:cauldron_surface,
 [
   id: :map,
   atlas: :my_game,
   focus: {x, y},
   cell: &MyGame.cell/1,
   movers: [{:ball, {7.42, 3.15}}],
   labels: [{"alice", {7.0, 2.0}, {255, 255, 0}}],
   flex: 1
 ]}
```

An art with frames is drawn at the frame showing on the clock. A label is text in
`Linocut.Font` over the world, or characters over the glyphs in text mode. The widget also
takes `:zoom`, `:mode`, `:projection`, `:layers`, `:volumes`, `:picture` and more.
`Cauldron2D.Drafter.Surface` documents each option.

The widget draws the same view two ways:

* **Pixels.** `image/3` composites the viewport and hands drafter one image as a kitty,
  iTerm2 or sixel escape sequence. `render/2` paints blank cells under it.
* **Text.** `render/2` draws two-cell glyphs in truecolour, from the same cells. Set
  `:mode` to `:braille`, `:half`, `:quad`, `:sextant` or `:octant` to draw block or braille
  characters instead.

Kitty transmits are zlib-compressed. Pass `compress: false` for a terminal whose kitty
support is partial.

On a kitty terminal whose cell size the session knows, the grid is one stored image. It
is sent again only when its tiles change. Each mover is a placement of a sprite that
`Cauldron2D.Drafter.Sprites.transmit/2` stored once, at a sub-cell pixel offset.
Elsewhere, the movers are composited into one image per frame.

## The picture

A scene with a `:picture` function draws its own frame. On a terminal that keeps images
(kitty, Ghostty, WezTerm, iTerm2), `Cauldron2D.Drafter.Client.Picture` decides what size
to draw it at and how to send it. Give the options as a list or a comma-separated
string:

* `native` draws the frame at the game's own size times the largest whole number that
  fits, and the terminal scales it to the pane. The game gives its size as the scene's or
  the look's `:native`.
* `native:N` draws it at the game's own size times `N`.
* `size:WxH` sets the game's own size, over what the game declares.
* `png` sends each frame as a PNG. A frame with at most 256 colours goes as a palette PNG.
  It takes more CPU to encode, so use it over ssh rather than locally.
* `swap` stores each frame before letting the last one go, so the pane never blanks.
* `gpu` and `window` draw on the graphics card. See below.
* `none` turns all of these off.

Without `native`, the frame is drawn at the pane's cells times the surface's density.

The client reads the options from the first of these that is set:

1. the `:picture` mount prop
2. `config :cauldron_2d_drafter, picture: "native:2,swap"`
3. the `CAULDRON_PICTURE` environment variable
4. the `:picture` key of the game's `look/0`
5. `Cauldron2D.Drafter.Client.Picture.default/0`, which is `native:2,swap`

The cost of a frame grows with its pixel count. Give a game whose frames are expensive to
draw a default of `native:1` in its `look/0`. Plain `native` on a large window can ask for
many times the game's own size.

A mix task can take a `--picture` flag and pass it through
`Cauldron2D.Drafter.Client.Picture.parse/1`.

## The graphics card

A scene can describe itself for the graphics card with a `:gpu` function as well as its
`:picture` (see `Cauldron2D.Client.Game` and
[`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu)). Such a game is drawn on the card by
default. You do not need a flag.

* When there is a card, the client draws the picture offscreen at the pane's pixels and
  shows it in the pane. This works on every terminal that shows pictures.
* When there is no card, or the renderer cannot open, the client draws the game's own
  `:picture`. Nothing changes for the player.
* A game that never gives a `:gpu` never starts a renderer.

Each player can change this in the settings screen's Drawing row, and a game can offer it
in its own menus. The setting is saved with the player's other settings. It has four
values: automatic (the default), software only, the card in the terminal, and the card in
a window of its own. In a window, keys pressed in the window reach the client as terminal
keys, with key releases, and the pane stays empty while the window is open.

A run can override the setting with the picture options `software`, `gpu` or `window`:

```
mix my_game --picture native:2,swap,window
CAULDRON_PICTURE=software mix my_game
```

A 2D game whose picture is a `Cauldron2D.DrawList` can give the same draw list to the
card with `Cauldron2D.Drafter.Client.Sprites`. It turns the items into
`CauldronGPU.Sprite`s for a `CauldronGPU.SpriteLayer` and uploads each picture the first
time it is drawn. Sprites land on the same pixels as the software picture. NidhOX
(`Nidhox.Gpu`) draws this way.

```elixir
def scene(view) do
  %{
    picture: fn size, _aspect -> MyGame.picture(view, size) end,
    gpu: fn target, cache, size, _aspect -> MyGame.Gpu.draw(view, target, cache, size) end
  }
end

def draw(view, target, cache, {width, height}) do
  cache = cache || Sprites.new()
  {sprites, cache} = Sprites.sprites(cache, target, view.items, &{&1, MyGame.raster(&1)})
  layer = %CauldronGPU.SpriteLayer{clear: {0.0, 0.0, 0.0, 1.0}, view: {0, 0, 320, 200}, sprites: sprites}
  {[{:layers, [layer]}], cache}
end
```

The renderer runs in its own OS process. `Cauldron2D.Drafter.Client.Stage` starts it
through `CauldronGPU.Host` and restarts it with its scene if it crashes. If you asked for
the card by name and it cannot be used, or the window is closed, the client draws the
game's own picture and shows a short note saying why.

## The setup page

`Cauldron2D.Drafter.Launcher` is a page shown before a game starts. The player sets the
things a game needs before it can run: where its data is, the skill, how it is drawn.
Play saves the choices, and later runs start straight away.

```elixir
fields = [
  %{key: :dir, label: "Game folder", kind: {:path, &MyGame.Assets.check/1},
    discover: &MyGame.Assets.discover/0, hint: "the folder holding the game's files"},
  %{key: :skill, label: "Skill", kind: {:choice, [{1, "easy"}, {2, "normal"}]}, default: 2},
  Cauldron2D.Drafter.Launcher.drawing_field()
]

case Cauldron2D.Drafter.Launcher.choose(MyGame.Client, fields, overrides: flags, player: name) do
  {:ok, values} -> start_the_game(values)
  :quit -> :ok
end
```

* The page opens on the first run, when a saved path no longer passes its check, or when
  you pass `launcher: true` (a game's `--launcher` flag).
* A path field's `:discover` function looks in the usual places when nothing is saved.
  `Launcher.steam_folders/1` lists where Steam keeps a game on macOS (also in CrossOver),
  Linux and Windows.
* Values given as `:overrides` (from flags) win for that run and are not saved.
* The choices are saved in `$XDG_CONFIG_HOME/<game>/launcher.config`. The Drawing field
  is also written into the player's settings, so the page and the game's options change
  the same setting.

On the page, ↑ and ↓ move, ← and → change a choice, Enter edits a path or presses a
button, and Escape quits.

## Tools

`mix cauldron.input` measures drafter's input path from a `DRAFTER_TRACE` log. With
`CAULDRON_TRACE` set, the client writes its keys, mouse events, input and frames to a
trace that `mix cauldron.report` reads.

## License

MIT
