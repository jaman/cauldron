# Cauldron2D.Net

This package puts `cauldron_2d` worlds on the network. The connection, the sessions and
the links are `cauldron_net`'s; this package adds `Cauldron2D.Net.Drawer`, which sends
each 2D scene to a client as a picture or as scene data, the pages and browser renderer
that show it, and `Cauldron2D.Net.Serve`, which serves a game with no web code of its
own.

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:cauldron_2d_net, "~> 0.4"}
  ]
end
```

It brings in `cauldron_net`, Phoenix, Bandit and the `gamepad` package.

## How it works

Each world is a process. A browser player is a Phoenix channel process. It joins the
world like any other player and runs the player's client on the server: the look, the
client's keys, the game's menu and fronts (`Cauldron.Client.Stage`,
`Cauldron.Client.Fronts`), and what the player holds (`Cauldron.Client.Controls`,
`Cauldron.Client.Party`). The browser sends raw input — keys down and up, mouse
buttons, wheel and moves, controller lines, actions held by name, an aim — and the
server reads it the way the terminal client reads its own.

What the browser shows is drawn by `Cauldron2D.Draw`, either on the server or in the
browser. Sessions send it through the drawer named by their `:drawer` option,
`Cauldron2D.Net.Drawer` for a 2D game, and the drawing setting decides who draws (see
"Who draws").

## Serving a game in one line

`Cauldron2D.Net.Serve` serves a game with no web code of its own: the pages at `/play`,
the player socket at `/socket`, and the channel, on Bandit. Write a mix task:

```elixir
defmodule Mix.Tasks.MyGame.Serve do
  use Mix.Task

  def run(argv), do: Cauldron2D.Net.Serve.run(MyGame.Client, argv, port: 4300)
end
```

`mix my_game.serve` serves the game at `http://localhost:4300/play` until the node
stops. It takes `--port PORT` and `--drawing server|client|split`. `run/3` also takes
`:before`, a function run once the application has started (to register the game's
worlds, for example), and `:secret_key_base`, the secret the player's saved settings
are signed with. `start/2` starts the endpoint under the calling process instead.

The pages name the player by the `name` query param (`/play?name=alice`) and keep it in
a cookie. A socket connection is named by its `username` or `name` connect param, and
is `guest` without one. A game whose players sign in writes its own endpoint, as below.

## Serving a game from your own endpoint

1. Mount the socket in your endpoint.
2. In your router, forward a path to the pages. To serve clients on other machines,
   forward another path to the API.
3. Define a socket module that `use`s `Cauldron.Net.Socket`.
4. Define a channel module that `use`s `Cauldron.Net.Channel` with
   `Cauldron2D.Net.Drawer` as its drawer.

```elixir
socket "/socket", MyGame.Web.UserSocket, websocket: true

forward "/play", Cauldron2D.Net.Pages, game: MyGame.Client, username: &MyGame.Web.Auth.username/1, token: &MyGame.Web.Auth.token/1, login: "/login"
forward "/api", Cauldron.Net.Api, login: &MyGame.Web.Auth.login/2, token: &MyGame.Web.Auth.token_for/1

defmodule MyGame.Web.UserSocket do
  use Cauldron.Net.Socket, channel: MyGame.Web.WorldChannel, verify: {MyGame.Web.Auth, :verify}
end

defmodule MyGame.Web.WorldChannel do
  use Cauldron.Net.Channel,
    game: MyGame.Client,
    drawer: {Cauldron2D.Net.Drawer, sheet_url: "/play/atlas.png"},
    topic: "world",
    audio: %{rate: 22_050, channels: 2}
end
```

The pages connect to the socket at the path in their `:socket` option. The default is
`"/socket"`. The pages serve the atlas at `atlas.png` under their own path; give that
path to the drawer as `:sheet_url`. The docs of `Cauldron2D.Net.Pages`,
`Cauldron2D.Net.Drawer`, `Cauldron.Net.Api`, `Cauldron.Net.Socket` and
`Cauldron.Net.Channel` list every option.

## Who draws

`Cauldron2D.Net.Drawing` decides who draws a served world's picture. It is set per
server:

* `:server` — the server draws everything with `Cauldron2D.Draw` and sends each frame
  as a truecolour PNG (`Cauldron2D.Net.Picture`). Every client sees exactly what the
  terminal draws, and the server pays for it in CPU and bandwidth. This is the default.
* `:client` — the client draws everything from scene data (`Cauldron2D.Net.Scene`). The
  server sends only what changed.
* `:split` — the client draws the world, and the server draws the screen (the scene's
  `:screen` and `:outlines`), sent as an overlay picture only when it changes.
* `[world: part, screen: part]`, each part `:server` or `:client`.

Set it in config:

```elixir
# config/runtime.exs
import Config

config :cauldron_2d_net, drawing: :client
```

The setting is read from the first of these that is set:

1. the `:drawing` option given: to `Cauldron2D.Net.Drawer` (as in
   `drawer: {Cauldron2D.Net.Drawer, drawing: :client}`), or to `Cauldron2D.Net.Serve`
   (its `--drawing` flag, then its `:drawing` option)
2. the `CAULDRON_DRAWING` environment variable: `server`, `client` or `split`
3. `config :cauldron_2d_net, drawing: ...`
4. `:server`

A scene with a `:picture` (one the game draws with a function of its own) is drawn by the
server whatever the setting. `Cauldron2D.Net.Drawn` turns each scene into what goes to
one client under the setting, at most one picture or scene per frame interval.

## The browser renderer

`priv/static/draw/*.js` is `Cauldron2D.Draw` in JavaScript. It draws a scene from the
data `Cauldron2D.Net.Scene` writes and gives the same bytes `Cauldron2D.Draw.picture/3`
gives. The world page loads it when the client draws. The files set up
`window.CauldronDraw` and are loaded in this order, before `cauldron.js`:

```
core.js volume.js surface.js parallax.js screen.js iso.js oblique.js mode7.js first_person.js draw.js
```

`Cauldron2D.Net.Pages` serves them at `draw/<file>`. The atlas the renderer draws from
is `Cauldron2D.Net.Atlas`: every picture of the atlas (frames, faces, poses, font
glyphs) packed onto one PNG, with an index of where each sits.

`test/js` holds a check that runs the renderer in Node against pictures the Elixir side
drew from the same scene, byte for byte. Make fixtures in a game's directory:

```
mix run ../../cauldron_2d_net/test/js/fixtures.exs Beast.Client journey ../../cauldron_2d_net/test/js/fixtures/beast
```

The arguments are the client module, a world id, the output directory and, optionally,
how many frames to run first (default 40). Then, from `cauldron_2d_net`:

```
node test/js/run.mjs
```

It prints, per scene, `ok` or how many pixels differ from the expected picture, writes
the expected picture, the actual one and their difference as PNGs in each scene's `out`
directory, and exits non-zero when any scene differs. An argument such as
`node test/js/run.mjs parade/play-iso` runs only the scenes whose `game/scene` name
contains it. `test/js/README.md` describes the fixtures.

## Modules

| Module | What it does |
|---|---|
| `Cauldron2D.Net.Serve` | Serves a game to browsers and desktops with no web code of the game's own. |
| `Cauldron2D.Net.Pages` | Serves the pages around the worlds: title, lobby, world, settings and guide, and the game's own pages. It is a plug your router forwards a path to. It builds the pages from your `Cauldron.Client.Game`. |
| `Cauldron2D.Net.Drawer` | The `Cauldron.Net.Drawer` of a 2D game: the sheet, who draws, and each scene as a picture or scene data. |
| `Cauldron2D.Net.Reader` | Reads those pushes on the client side of a socket link, and keeps them in a link world's view. |
| `Cauldron2D.Net.RemoteScene` | Draws a remote world's view as a scene, for a game's client module. |
| `Cauldron2D.Net.Wire` | Reads the sheet and drawing messages for an Elixir client. |
| `Cauldron2D.Net.Drawing` | Reads who draws: the server, the client, or split. |
| `Cauldron2D.Net.Drawn` | Turns a scene into the pushes for one client under the drawing setting. |
| `Cauldron2D.Net.Picture` | Encodes a server-drawn picture as a truecolour PNG. |
| `Cauldron2D.Net.Scene`, `Scene.Items` | Write a scene as data a client draws itself, sending each cell kind once, and read it back into a `Cauldron2D.Draw` view. |
| `Cauldron2D.Net.Atlas` | Packs an atlas for a client that draws scenes itself, with tinted arts and tinted cells on request. |
| `priv/static/cauldron.js` | Runs the game in a browser. Call `Cauldron.mount(canvas, opts)`. |
| `priv/static/draw/*.js` | Draws a scene in the browser, as `Cauldron2D.Draw` does. |

The socket, channel, sessions, sound policy, API, links and load test are
`cauldron_net`'s; its README lists them.

## The pages

`Cauldron2D.Net.Pages` gives every screen a `Cauldron.Client.Game` describes:

* **Title.** The game's own title front (`fronts/1`) when it has one, drawn and run like
  a world on the channel's `front:title` topic (`world:front:title` with the default
  prefix); otherwise a page with the game's name. The
  game's `start/0` decides whether the browser opens on the title, the lobby or a world.
* **Lobby.** The worlds with their players, refreshed from `worlds.json`, and a chat
  panel on the lobby room when the game's `chat?/0` is not `false`.
* **World.** The canvas, the hud and the world's chat panel. A summary front the game
  draws itself replaces the end-of-round box.
* **Settings.** The key preset, the frame rate (`frame_rates/1`) and whether the pointer
  aims, kept in the browser and sent as join params. The game's menu can change the
  player's settings too; the channel pushes them back signed, and the page keeps them.
* **Guide** and the game's own pages.

## Joining a server from Elixir

Log in, start a `Link.World` for the server's world, and join it as a player:

```elixir
{:ok, token} = Cauldron.Net.Remote.login("http://arcade:2280/api", "alice", "secret", false)
{:ok, world} =
  Cauldron.Net.Link.World.start(
    url: "http://arcade:2280",
    token: token,
    world: "pit",
    drawer: {Cauldron2D.Net.Drawer, atlas: :my_game}
  )

:ok = Cauldron.Player.join(world, "alice", %{username: "alice"})
```

`Link.World` opens a WebSocket for each player and plays the sound that comes with the
frames. A view it sends is `%{remote: remote, world: name}`. The game's client module
draws it with `Cauldron2D.Net.RemoteScene.scene/1` and `Link.World`'s `hud/1` and
`outcome/1`:

```elixir
def scene(%{remote: _} = view), do: Cauldron2D.Net.RemoteScene.scene(view)
def scene(view), do: MyGame.Scene.of(view)
```

The scene is a `:picture`: the server's picture scaled to the pane, or, from a server
that leaves the drawing to its clients, the scene drawn here with the local atlas. Give
the drawer `:atlas`, the game's atlas installed on this node, for such a server.
Without it the server closes the link.

### Links

`Link.Socket` and `Link.Local` carry one player. The player's raw input goes up through
`key/4` (a key as `Cauldron.Input` names it, its modifiers, and whether it went down),
`mouse/2` (`%{type: :mouse_down | :mouse_up, button}`, `%{type: :scroll, direction}` or
`%{type: :move}`, each with `at`, the pointer as fractions of the picture),
`pad_event/2` (a `Gamepad.Wire` event), `hold/4` (an action held by name),
`pane/2` (the tiles the client shows at zoom 1), `pan/2`, `configure/2` (settings changed
beside the world), `say/2` (a chat line), `levels/3`, `pause/1` and `leave/1`.
`Link.Socket` also has `aim/2`, a world point or `nil`.

The owner receives `{:cauldron_link, ...}` messages: the sheet, who draws, each tick's
status, and a picture or a scene (with an overlay when the server draws the screen);
where the client goes, settings, clipboard text, chat, the round's end and the link
closing. Start either link with `drawer: Cauldron2D.Net.Drawer` for the sheet, pictures
and scenes. `Cauldron.Net.Link.Socket`, `Cauldron.Net.Link.Local` and
`Cauldron2D.Net.Drawer` list each message.

## The wire

Server to client. `sheet`, `drawing`, `picture`, `scene`, `overlay`, `tinted` and
`tinted_cell` are `Cauldron2D.Net.Drawer`'s; the rest are every session's.

| Event | Payload |
|---|---|
| `sheet` | The `Cauldron2D.Net.Atlas` index: `url`, `tile`, `void`, `width`, `height`, `arts`, `fonts`, `label_font`, `tints`, `tallest`. |
| `drawing` | `{world, screen}`, each `"server"` or `"client"`. Sent once per world. |
| `status` | The hud rows as `[[text, "#rrggbb" or null]…]` runs, `tags` when any row has one, `over`, `subject` and `focus` (`Cauldron.Net.Frame`). |
| `picture` (binary) | A PNG of the client's pane, drawn by the server. |
| `scene` | A `Cauldron2D.Net.Scene` payload for the client to draw. |
| `overlay` (binary) | The screen drawn by the server over a client-drawn world, or empty when there is none. |
| `tinted`, `tinted_cell` | An art or a cell kind through one of the atlas's tints, as a base64 PNG, sent before the first scene that uses it. |
| `audio` | `{rate, channels}` of the PCM that follows, or `{off: true}`. A join param `audio` of `{rate, channels}` asks for a format; `false` asks for no sound. |
| `pcm` (binary) | Signed 16-bit little-endian PCM in the `audio` format. |
| `go` | `{to}`: `"world"` with `id`, `"lobby"`, `"settings"`, `"guide"`, `"title"` or `"quit"`. |
| `front` | `{screen: "summary"}`: the round is over and the game's summary front runs on this channel. |
| `world` | `{id}`: the world moved the player to another world. |
| `settings` | `{sfx, music, saved}`: the player's settings changed; `saved` is signed for the browser to send back as the join param `saved`. |
| `clipboard` | `{text}` for the player's clipboard. |
| `chat_history`, `chat`, `talk` | A room's last messages, one new message, and the talk key asking for a line. |

Client to server:

| Event | Payload |
|---|---|
| `pane` | `{columns, rows}`: the tiles the client shows at zoom 1. Nothing is drawn before it. |
| `key` | `{key, mods, down}`: a `KeyboardEvent.key`, modifiers of `"ctrl"`, `"shift"`, `"alt"`, `"meta"`, and whether it went down. |
| `mouse` | `{button, down}`, `{wheel: "up" or "down"}` or `{move: true}`, each with `at`, the pointer as fractions of the picture. |
| `padline` | `{line}`: a `Gamepad.Wire` line from the page's controllers. |
| `hold` | `{action, down, strength}`: an action held by name, as a touch button holds it. |
| `aim` | `{at}`: a world point, or `null`. |
| `pan`, `recentre` | `{x, y}` as fractions of the pane, for a watching player. |
| `configure` | `{preset, pointer}`: settings changed beside the world. |
| `say` | `{text}`: a chat line. |
| `levels` | `{sfx, music}` |
| `music` | `{on}`: the music off, or back on at its level. |
| `pause` | `{}`: pause or resume a world the player has to themselves. |

## cauldron.js

`Cauldron.mount(canvas, opts)` joins the channel and draws what arrives: the server's
picture, or the scene drawn with `CauldronDraw` when the client draws. The pages mount it
for you; a page of your own mounts it with these options:

* `topic`, `params` (the join params), `socketUrl`, `socketParams`
* `scale` (CSS pixels a tile), `fit` (fill the canvas's parent at the screen's pixel
  ratio), `hud` (an element for the hud rows)
* `audio` (`{rate, channels}` or `false`), `watching` (the view can be panned)
* `touch`: `{zones, tilt}`, on-screen buttons and sticks that hold actions, and tilt
  steering with `{range, deadzone, distance, smoothing, invert}`
* `pad`, the options `gamepad.js`'s `Gamepad.watch` takes
* `pinch: false` turns off pinch zoom; `aimEvery` is the milliseconds between pointer
  messages
* callbacks: `onJoin`, `onError`, `onOver`, `onGo`, `onFront`, `onWorld`, `onSettings`,
  `onChat`, `onChatHistory`, `onTalk`, `onStats`

Keys go to the server as they go down and up, and the mouse's buttons, wheel and moves
with the pointer as fractions of the picture. Controllers the page sees (`gamepad.js`,
served at `gamepad.js`) go up as `Gamepad.Wire` lines, and the server plays them by the
game's padmap. The server holds the keymap, the padmap and the zoom.

The handle `mount` returns has:

* `levels(sfx, music)`, `music(on)`, `unlockSound()`
* `zoomIn()`, `zoomOut()`, `panBy(fx, fy)` (fractions of the pane, while watching),
  `recentre()`
* `say(text)`: a line in the world's chat
* `aim([x, y])` sets the aim to a world point, `null` lets go; `hold(action, down,
  strength)` holds or releases an action, `strength` from `0` to `1`. A page uses them
  for an input source of its own.
* `focus()`, `input()`, `stats()`, `stop()`

## License

MIT
