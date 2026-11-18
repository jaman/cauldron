# Serving a game in a browser

`cauldron_2d_net` puts `cauldron_2d` worlds in a browser. The connection, the sessions and
the links are [`cauldron_net`](https://hexdocs.pm/cauldron_net)'s; this package adds the
drawer that sends a 2D scene, the pages around the worlds, the browser renderer that draws
a scene without the server, and a runner that serves a game with no web code of its own.

Each browser player is a Phoenix channel process. It joins the world like any other player
and runs the player's client on the server — the look, the client's keys, the game's menu
and fronts — so the game does not know a browser is there. The browser sends raw input:
keys down and up, mouse buttons, wheel and moves, controller lines, actions held by name,
an aim.

## Serving with no code of your own

`Cauldron2D.Net.Serve.run/2` serves a game's pages at `/play`, its player socket at
`/socket`, and its channel, on Bandit:

```elixir
defmodule Mix.Tasks.MyGame.Serve do
  use Mix.Task

  def run(argv), do: Cauldron2D.Net.Serve.run(MyGame.Client, argv, port: 4300)
end
```

`mix my_game.serve` prints the address, serves the game at `http://localhost:4300/play`
until the node stops, and takes `--port PORT` and `--drawing server|client|split`.

| Option | Holds | Default |
| --- | --- | --- |
| `:port` | The port to listen on, when `--port` is not given | `4300` |
| `:drawing` | Who draws, when `--drawing` is not given | The environment and config |
| `:before` | A function run once the application has started | None |
| `:secret_key_base` | The secret a player's saved settings are signed with | One made for this run |
| `:drawer` | The drawer, `module` or `{module, opts}` | `Cauldron2D.Net.Drawer` |

`:before` is where a game registers its worlds. It runs once the application has started and
before the endpoint does, so the worlds are there when the first player arrives. Without
`:secret_key_base` the pages can sign settings only for this run, so settings a player saved
in a browser last for the run; a game that keeps them across restarts gives the endpoint a
secret of its own, which means writing its own endpoint, as below.

The pages name the player by the `name` query param — `/play?name=alice` — and keep it in a
cookie for the pages after it. A socket connection is named by its `username` or `name`
connect param, and is `guest` without one. A game whose players sign in writes its own
endpoint.

`Serve.start/2` is the same thing under the calling process, for a supervision tree, with
`:port`, `:drawing`, `:secret_key_base` and `:drawer`. It answers `{:ok, pid}`, or
`{:error, reason}`.

## In your own Phoenix app

Four pieces, in the app's own names.

```elixir
# lib/my_game_web/endpoint.ex
socket("/socket", MyGameWeb.UserSocket, websocket: true)

# lib/my_game_web/router.ex
forward("/play", Cauldron2D.Net.Pages,
  game: MyGame.Client,
  username: &MyGameWeb.Auth.username/1,
  token: &MyGameWeb.Auth.token/1,
  login: "/login"
)

forward("/api", Cauldron.Net.Api,
  login: &MyGameWeb.Auth.login/2,
  token: &MyGameWeb.Auth.token_for/1
)
```

```elixir
defmodule MyGameWeb.UserSocket do
  use Cauldron.Net.Socket,
    channel: MyGameWeb.WorldChannel,
    verify: {MyGameWeb.Auth, :verify}
end

defmodule MyGameWeb.WorldChannel do
  use Cauldron.Net.Channel,
    game: MyGame.Client,
    drawer: {Cauldron2D.Net.Drawer, sheet_url: "/play/atlas.png"},
    topic: "world",
    audio: %{rate: 22_050, channels: 2}
end
```

`Cauldron.Net.Socket` takes `:channel`, the module a `"world:"` topic is routed to;
`:verify`, a `{module, function}` given the connect params and answering
`{:ok, %{username: name}}` — with `:settings` when the game keeps them — or `:error`;
`:topic`, the topic prefix, `"world"` by default; and `voice: true` for `Cauldron.Net.Voice`.

`Cauldron.Net.Channel` takes `:game`, the client module; `:drawer`, this package's drawer
with its options; `:topic`, again the prefix; and `:audio`, the PCM format the browser gets
when it asks for none, `%{rate: 44_100, channels: 2}` by default. A player joins
`"world:<id>"`, `"world:front:title"` for the game's own title, or `"world:chat:lobby"` for
the lobby's chat room.

The `/api` forward is only needed to let clients on other machines join — an Elixir client
with `Cauldron.Net.Remote`, `Cauldron.Net.Link.World`, or a desktop window joining over the
socket. A game that serves only browsers leaves it out.

This is also the path to take when the pages must sit under a path of the app's own. The
pages build their links from the path they are mounted at, so `forward "/game", ...` gives
`/game/settings`, `/game/atlas.png` and the rest without further configuration.

## Pages and their options

`Cauldron2D.Net.Pages` serves every screen the game's `Cauldron.Client.Game` describes: the
title, the lobby with its worlds and chat, the world with its canvas and hud, settings, the
guide, and the game's own pages at `page/<key>`.

| Option | Holds | Default |
| --- | --- | --- |
| `:game` | The client module. Required | — |
| `:username` | A function from the conn to the player's name, or `nil` | The conn's `:username` assign |
| `:token` | A function from the conn to the socket's token | None |
| `:login` | Where to send a visitor with no name | None, and the page says so |
| `:socket` | The socket's path | `"/socket"` |
| `:topic` | The channel topic prefix | `"world"` |
| `:scale` | Pixels a tile on the canvas | `32` |
| `:nav` | `{label, path}` links in every page's header | Worlds, settings, guide |
| `:drawer` | The drawer the channel uses | `Cauldron2D.Net.Drawer` |

`:nav` set to `[]` leaves the header to an app whose pages are its own.

The pages also serve what the browser needs: `atlas.png`, `cauldron.js`, the scene
renderer at `draw/<file>`, `gamepad.js`, `phoenix.min.js`, `voice.js`, and `worlds.json` for
the lobby to refresh from. `cauldron.js` is the browser's player: the pages mount it on the
canvas with the player's settings and the game's padmap, and it draws what arrives.

## Who draws

The world can be drawn on the server, as a picture, or in the browser, from scene data.
`Cauldron2D.Net.Drawing` decides, and `Cauldron2D.Net.Drawn` turns each scene into the
pushes for one client under that setting.

| Setting | Server sends | Gives |
| --- | --- | --- |
| `:server` | A truecolour PNG of the pane | Every client sees exactly what the terminal draws; the server pays in CPU and bandwidth |
| `:client` | The scene, as data | The browser draws; the server sends only what changed |
| `:split` | The scene, and the screen as an overlay picture | The browser draws the world, the server the scene's `:screen` and `:outlines` |
| `[world: part, screen: part]` | Either, per part | A mix of the two, each part `:server` or `:client` |

It is read from the first of these that is set: the `:drawing` option given to
`Cauldron2D.Net.Drawer` or to `Cauldron2D.Net.Serve` — its `--drawing` flag first, then its
option — then `CAULDRON_DRAWING` (`server`, `client` or `split`), then
`config :cauldron_2d_net, drawing: ...`, then `:client`.

```elixir
# config/runtime.exs
import Config

config :cauldron_2d_net, drawing: :client
```

A scene with a `:picture` — one the game draws with a function of its own — is drawn by the
server whatever the setting. The browser shows the picture it is sent.

The channel pushes `"drawing"` once per world, as `%{world: part, screen: part}`, so a page
knows which side is drawing before the first frame arrives.

## The atlas

A browser that draws scenes needs the game's pictures. `Cauldron2D.Net.Atlas` packs every
picture of the atlas — frames, faces, poses, font glyphs — onto one PNG, with an index of
where each sits, and `Cauldron2D.Net.Pages` serves that PNG at `atlas.png` under its own
path. The drawer names the URL to the browser as `:sheet_url`:

| Where the pages are | `:sheet_url` |
| --- | --- |
| `forward "/play", Cauldron2D.Net.Pages, ...` | `"/play/atlas.png"` |
| `Serve.run/2`, which forwards `/play` itself | `"/play/atlas.png"`, set for you |
| `forward "/game", ...` | `"/game/atlas.png"` |

The default is `"/atlas.png"`, which is right only when the pages are at the root. A
`{module, function}` may be given instead, called each time a sheet is sent, for a URL that
changes with the sheet — a cache-busting digest, say.

The sheet is pushed when a player joins and again when the game's atlas changes, so a game
that installs a new atlas mid-run does not need to make its players reload. The browser
renderer in `priv/static/draw/*.js` draws from that sheet, and the picture it makes from a
scene is the one `Cauldron2D.Draw.picture/3` makes from the same scene on the server.

## Where to go next

| You want to | Read |
| --- | --- |
| Play the same game in a terminal | [`cauldron_2d_drafter`'s guide](https://hexdocs.pm/cauldron_2d_drafter/terminal.html) |
| Play the same game in a desktop window | [`cauldron_2d_wx`'s guide](https://hexdocs.pm/cauldron_2d_wx/window.html) |
| Understand the socket, the channel and the sessions | [`cauldron_net`](https://hexdocs.pm/cauldron_net) |
| The drawer's messages, one by one | `Cauldron2D.Net.Drawer` and `Cauldron2D.Net.Wire` |
| Join a served world from Elixir | `Cauldron.Net.Link.World` and `Cauldron2D.Net.RemoteScene` |
| Draw the game | [`cauldron_2d`'s tutorial](https://hexdocs.pm/cauldron_2d/tutorial.html) |
