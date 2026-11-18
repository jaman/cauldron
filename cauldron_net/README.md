# Cauldron.Net

This package puts Cauldron worlds on the network, whatever the game draws with. A server
uses it to let browsers, desktop windows and terminals on other machines play its worlds.
A client uses it to reach a server, over a WebSocket or from node to node.

What a client is sent to show each scene is not this package's: a drawer
(`Cauldron.Net.Drawer`) decides it. `cauldron_2d_net` has the drawer for 2D games, the
browser pages that show its pictures and scenes, and a server for a game in one line.
Most games depend on that package rather than this one.

## Installation

```elixir
def deps do
  [
    {:cauldron_net, "~> 0.4"}
  ]
end
```

It brings in Phoenix, Mint and the `gamepad` package.

## How it works

Each world is a process. A browser player is a Phoenix channel process
(`Cauldron.Net.Channel`). It joins the world like any other player and runs the player's
client on the server (`Cauldron.Net.Session`): the look, the client's keys, the game's
menu and fronts, and what the player holds. The browser sends raw input (keys down and
up, mouse buttons, wheel and moves, controller lines, actions held by name, an aim), and
the server reads it the way the terminal client reads its own. A title or summary the
game draws itself runs the same way (`Cauldron.Net.FrontSession`).

Each frame, the session pushes the frame's status (hud rows, outcome, subject, focus) and
then whatever its drawer pushes to show the scene. The session tells the drawer the
client's pane and frame rate, and passes it any message its process gets that the
session does not know, such as the game's art changing.

```elixir
defmodule MyGame.Web.UserSocket do
  use Cauldron.Net.Socket, channel: MyGame.Web.WorldChannel, verify: {MyGame.Web.Auth, :verify}
end

defmodule MyGame.Web.WorldChannel do
  use Cauldron.Net.Channel, game: MyGame.Client, drawer: Cauldron2D.Net.Drawer
end
```

## Drawers

A drawer is a module implementing `Cauldron.Net.Drawer`, named with the `:drawer` option
wherever a session or a link starts: a module, or `{module, opts}` with options of its
own. Its callbacks cover both ends:

* **The server.** `open/2` gives the drawer's state and the first pushes; `draw/2` and
  `tick/2` give the pushes that show a scene, from the props the game's view draws it
  with (`c:Cauldron.Client.View.props/4`); `pane/2`, `rate/2`, `world_at/3`, `changed/3`,
  `close/2`, and `colour/1` for the colours a hud names.
* **A client in this node.** `local/2` turns a push into the messages
  `Cauldron.Net.Link.Local` gives its owner.
* **A client over the socket.** `reader/1` and `read/4` read the pushes
  `Cauldron.Net.Link.Socket` receives; `remote/2` keeps them in a link world's view.

## Joining a server from Elixir

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

`Link.World` stands in for the server's world in this VM. It opens a WebSocket for each
player (`Link.Socket`), plays the sound that comes with the frames, and sends each
player views of `%{remote: remote, world: name}`. `Link.World.hud/1` and `outcome/1`
read the hud and the outcome from such a view; the drawer's package draws its scene.

`Link.Socket` and `Link.Local` carry one player. The player's input goes up through
`key/4`, `mouse/2`, `pad_event/2`, `hold/4`, `aim/2`, `pane/2`, `pan/2`, `configure/2`,
`say/2`, `levels/3`, `pause/1` and `leave/1`. The owner receives `{:cauldron_link, ...}`
messages: each tick's status, where the client goes, settings, clipboard text, chat, the
round's end, the link closing, and the drawer's own messages.

## Sound

`Cauldron.Net.Audio` sets the server's sound policy: music per session, per world (one
stage a world, `Audio.Shared`), or none; effects per session or none. `Audio.Governor`
lowers the rate when the node is busy. The channel sends the sound as binary `pcm`
pushes; `Cauldron.Net.Sound` plays what a link delivers through this machine's speaker.

## Modules

| Module | What it does |
|---|---|
| `Cauldron.Net.Socket` | Defines your socket module when you `use` it. A verify function gives the player's name and settings. |
| `Cauldron.Net.Channel` | Defines your channel module when you `use` it. One channel runs a world, the game's title front, or the lobby chat. |
| `Cauldron.Net.Session` | Runs one player's time in a world: join, frames, raw input, the pane, chat, levels, leave. |
| `Cauldron.Net.FrontSession` | Runs one player on a title or summary the game draws itself (`Cauldron.Front`). |
| `Cauldron.Net.Drawer` | The behaviour a drawer implements. |
| `Cauldron.Net.Frame` | Gives a frame's status: the hud rows, the outcome, the subject and the focus. |
| `Cauldron.Net.Keys` | Turns a browser's `KeyboardEvent.key` into the key `Cauldron.Input` names, and back. |
| `Cauldron.Net.Audio` | Sets the server's sound policy. |
| `Cauldron.Net.Api` | Answers clients on other machines over plain HTTP: `POST /token`, `GET /worlds`, `GET /stats` and `GET /leaders`. It is a plug your router forwards a path to. |
| `Cauldron.Net.Remote` | Calls that API from a client, or asks a connected node instead. |
| `Cauldron.Net.Remote.Worlds` | Names worlds on another node or server: `{:via, Cauldron.Net.Remote.Worlds, {:node, node, id}}` or `{:url, url, token, id, opts}`. |
| `Cauldron.Net.Wire` | Encodes and decodes the channel protocol, and reads the status and `go` messages, for an Elixir client. |
| `Cauldron.Net.Link.Socket` | Connects an Elixir client to a server over its WebSocket. |
| `Cauldron.Net.Link.Local` | Connects an Elixir client to a world process, on this node or a connected one. |
| `Cauldron.Net.Link.World` | Stands in for a server's world as a process in this VM. |
| `Cauldron.Net.Sound` | Plays the PCM a link delivers through this machine's speaker. |
| `Cauldron.Net.Load` | Runs a load test over the wire, adding sessions until the worlds or the frames fall behind. |

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
