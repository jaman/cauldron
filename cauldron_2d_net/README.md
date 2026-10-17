# Cauldron2D.Net

This package puts `cauldron_2d` worlds on the network. A server uses it to serve its
worlds to browsers, desktop windows and terminals on other machines. A client uses it
to reach a server, over a WebSocket or from node to node.

## Installation

Add the dependencies:

```elixir
def deps do
  [
    {:cauldron_2d_net, "~> 0.3"},
    {:phoenix, "~> 1.8"}
  ]
end
```

## How it works

Each world is a process. A browser player is a Phoenix channel process. It joins the
world like any other player and forwards what the world sends. The browser fetches a
sprite sheet once and draws from it. After that the server sends positions, hud text
and sound, never pixels.

## How it fits

Your game implements `Cauldron2D.Client.Game` from `cauldron_2d` once, for every front
end. It brings its own Phoenix endpoint and login. `Cauldron2D.Net.Pages` gives it the
web pages. Each player's `Cauldron2D.Audio` runs on the server. Its sound goes to the
channel through `TuningFork.Sink.Process` and travels on the same socket as the frames.

The same server also serves players outside a browser. `cauldron_2d_wx` draws the game
in a desktop window, joined through `Link.Socket` or `Link.Local`. Any client that joins
a `Cauldron2D.World` can also join a world on another server or node. The terminal
client of `cauldron_2d_drafter` is one such client. To do this, have the game's
`worlds/1` give a `Link.World` or a `Remote.Worlds` name as an entry's `:world`.

| Module | What it does |
|---|---|
| `Cauldron2D.Net.Pages` | Serves the pages around the worlds: title, lobby, world, settings and guide. It is a plug your router forwards a path to. It builds the pages from your `Cauldron2D.Client.Game`. |
| `Cauldron2D.Net.Socket` | Defines your socket module when you `use` it. A verify function gives the player's name and settings. |
| `Cauldron2D.Net.Channel` | Defines your channel module when you `use` it. It pushes frames as JSON and sound as binary PCM. |
| `Cauldron2D.Net.Session` | Runs one player's time on a channel: join, frames, input, levels, leave. |
| `Cauldron2D.Net.Keys` | Turns a game's keymap into `KeyboardEvent.code` names. |
| `Cauldron2D.Net.Sheet` | Packs a `Cauldron2D.Atlas` into one PNG, with an index of where each art sits. |
| `Cauldron2D.Net.Frame` | Gives the wire form of the static map and of one tick's frame. |
| `Cauldron2D.Net.Audio` | Sets the server's sound policy. Music plays per session, per world (`Audio.Shared` runs one stage for a world), or not at all. `Audio.Governor` lowers the rate when the node is busy. Effects play per session or not at all. |
| `Cauldron2D.Net.Load` | Runs a load test over the wire. It adds sessions until the worlds or the frames fall behind. It keeps every report as JSON lines. |
| `Cauldron2D.Net.Api` | Answers clients on other machines over plain HTTP: `POST /token`, `GET /worlds`, `GET /stats` and `GET /leaders`. It is a plug your router forwards a path to. |
| `Cauldron2D.Net.Remote` | Calls that API from a client: `login/4`, `worlds/1`, `stats/1`, `leaders/4`. `node_worlds/1`, `node_world/2` and `node_leaders/5` ask a connected node instead. |
| `Cauldron2D.Net.Wire` | Encodes and decodes the channel protocol and the frame, map and sheet, for an Elixir client. |
| `Cauldron2D.Net.Link.Socket` | Connects an Elixir client to a server over its WebSocket. |
| `Cauldron2D.Net.Link.Local` | Connects an Elixir client to a world process, on this node or a connected one. Frames arrive in the same form as from `Link.Socket`. |
| `Cauldron2D.Net.Link.World` | Stands in for a server's world as a process in this VM. You join it like any `Cauldron2D.World`. `scene/2`, `hud/1`, `outcome/1` and `labels/1` turn what it sends into what a `Cauldron2D.Client.Game` draws. |
| `Cauldron2D.Net.Remote.Worlds` | Names worlds on another node or server. Use `{:via, Cauldron2D.Net.Remote.Worlds, {:node, node, id}}` or `{:via, Cauldron2D.Net.Remote.Worlds, {:url, url, token, id}}`. |
| `Cauldron2D.Net.Sound` | Plays the PCM a link delivers through this machine's speaker. |
| `priv/static/cauldron.js` | Draws the game in a browser. Call `Cauldron.mount(canvas, opts)`. It handles the channel, drawing, keys, pointer, game controllers, touch zones, tilt steering and Web Audio. |

## Serving a game

1. Mount the socket in your endpoint.
2. In your router, forward a path to the pages. To serve clients on other machines,
   forward another path to the API.
3. Define a socket module that `use`s `Cauldron2D.Net.Socket`.
4. Define a channel module that `use`s `Cauldron2D.Net.Channel`.

```elixir
socket "/socket", MyGame.Web.UserSocket, websocket: true

forward "/play", Cauldron2D.Net.Pages, game: MyGame.Client, username: &MyGame.Web.Auth.username/1, token: &MyGame.Web.Auth.token/1, login: "/login"
forward "/api", Cauldron2D.Net.Api, login: &MyGame.Web.Auth.login/2, token: &MyGame.Web.Auth.token_for/1

defmodule MyGame.Web.UserSocket do
  use Cauldron2D.Net.Socket, channel: MyGame.Web.WorldChannel, verify: {MyGame.Web.Auth, :verify}
end

defmodule MyGame.Web.WorldChannel do
  use Cauldron2D.Net.Channel, game: MyGame.Client, topic: "world", audio: %{rate: 22_050, channels: 2}
end
```

The pages connect to the socket at the path in their `:socket` option. The default is
`"/socket"`. Mount the socket at that path in the endpoint. The docs of
`Cauldron2D.Net.Pages`, `Cauldron2D.Net.Api`, `Cauldron2D.Net.Socket` and
`Cauldron2D.Net.Channel` list every option.

## Joining a server from Elixir

Log in, start a `Link.World` for the server's world, and join it as a player:

```elixir
{:ok, token} = Cauldron2D.Net.Remote.login("http://arcade:2280/api", "alice", "secret", false)
{:ok, world} = Cauldron2D.Net.Link.World.start(url: "http://arcade:2280", token: token, world: "pit")
:ok = Cauldron2D.Player.join(world, "alice", %{username: "alice"})
```

`Link.World` opens a WebSocket for each player. It plays the sound that comes with the
frames. It matches arts to the local atlas by name, so both sides must draw from the
same atlas.

## The wire

| Event | Payload |
|---|---|
| `sheet` | `{url, tile, columns, void, arts: {name: index}, frames: [[x, y]…], anim: {"index": {indices: [index…], fps}}}` |
| `map` | `{width, height, tile, wrap, rows: [[index…]…]}`. It is sent once. Index 0 means an empty cell. |
| `frame` | `{focus: [x, y], movers: [[index, x, y]…], labels: [[text, x, y, "#rrggbb", scale]…], hud: [[[text, "#rrggbb" or null]…]…], over: {title, lines} or null}`. `tags: [name or null…]` is added when any hud row has a tag. `subject` is added when the scene names what the focus follows. |
| `audio` | `{rate, channels}` of the PCM that follows, or `{off: true}` when there is no sound. A join param `audio` of `{rate, channels}` asks for a format; `false` asks for no sound. |
| `pcm` (binary) | Signed 16-bit little-endian PCM in the `audio` format. |
| `input` (browser → server) | `{held: [action…], aim: [x, y] or null}`, with an optional `strength` for analog actions. |
| `levels` (browser → server) | `{sfx, music}` |
| `music` (browser → server) | `{on: true or false}`. It turns the music off, or back on at its level. Effects are not changed. |
| `pause` (browser → server) | `{}`. It pauses or resumes a world the player has to themselves. |

## The view in the browser

`Cauldron.mount(canvas, opts)` draws the world around the frame's focus. It draws the
static map from cached chunks, and only the chunks in view. This works at any map size,
zoom and screen pixel ratio. Movers, labels and animated cells are drawn over the map.

The focus is always the centre of the view. At a map's edge, or when zoomed out past
the whole map, the void shows around it. Zooming out and back in returns to the same
view.

**Zoom.** Pass `zoom: {min, max, keys, wheel, pinch}` to let the player zoom. `+` or
`=` zooms in and `-` zooms out. The wheel and a pinch also zoom. `0` goes back to
`scale`. From the page, call `game.zoom(tile)` or `game.zoomBy(factor)`.

**Watching.** Put `spectate` in the join `params`, or pass `watching: true`. The
player can then move the view. The arrows pan it, and so does a drag with the mouse or
one finger. The wheel and a pinch zoom about the pointer or the fingers. `0` recentres
the view. From the page, call `game.panBy(dx, dy)` with tiles, or `game.recentre()`.
When a frame's `subject` changes, the pan is dropped and the new subject is centred.

**Playing.** The view stays on the focus. The aim is the world point under the mouse.
It is worked out again after every draw, so a moving focus under a still mouse keeps
aiming ahead of it.

**Sound.** Call `game.levels(sfx, music)` to set the levels. Call `game.music(on)` to
turn the music off or back on.

**Input from the page.** The handle lets a page add its own input source, such as its
own tilt model or a WebHID reader.

* `game.aim([x, y])` sets the aim to a world point. `null` lets go. It drops the
  mouse's aim, as a game controller does.
* `game.hold(action, down, strength)` holds or releases an action. `strength` is an
  analog value from `0` to `1`.
* `game.focus()` returns the current focus in world units.
* `game.input()` returns what would be sent now: `held`, `aim` and `strength`.

The built-in tilt steering takes `touch: {tilt: {range, deadzone, distance, smoothing,
invert}}`. `invert` flips the up-down axis.

**Game controllers.** A game controller holds actions like the keys do. The world page
loads `gamepad.js` from the `gamepad` package, served at `/gamepad.js`. It passes
`padmap`, which is the game's `padmap/1` as `Cauldron2D.Net.Keys.browser_padmap/1`
writes it. The padmap maps buttons by their wire names to actions, and each direction
of an axis to actions. A page that mounts the canvas itself passes the same `padmap`.

* A button holds its actions at full strength.
* An axis past the deadzone holds its direction's actions at its magnitude. That
  magnitude is sent as the input's `strength`. Set the deadzone with `pad: {deadzone}`;
  the default is 0.3.
* When a controller goes away, everything it held is released.
* A stick bound to `aim` aims instead. It aims eight tiles from the focus, the way it
  points, and follows the focus while held. With a `push` on the binding it also holds
  an action past its ring, harder the further it goes. An on-screen thumbstick's
  `push` works the same way.

## License

MIT
