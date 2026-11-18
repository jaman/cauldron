# Networking

A Cauldron world is a process. `cauldron_net` carries it to players who are not in the
same VM: a browser through a Phoenix channel, an Elixir program through a WebSocket or a
local link. It carries the world and the player's input; what a client is sent to *show*
is a drawer's business, and `cauldron_2d_net` supplies the drawer for 2D games.

Most games use `cauldron_2d_net`; read this when writing a drawer or an Elixir client.

## A player on another machine

The world runs where the game runs. A browser player is a channel process
(`Cauldron.Net.Channel`) that joins the world like any other player. The channel keeps a
session (`Cauldron.Net.Session`): the player's stage, menu, settings and what they hold.
The session sends the world their input and receives a frame for each tick it sends them.

The session turns a frame into a `"status"` push (hud rows, outcome, subject, focus) and
the pushes its drawer gives for the scene. The browser draws those. Sound is synthesised
on the server and sent as binary `"pcm"` pushes.

## The socket and the channel

A socket module is how browsers connect. A channel module is one player's room.

```elixir
defmodule MyGame.Web.UserSocket do
  use Cauldron.Net.Socket,
    channel: MyGame.Web.WorldChannel,
    verify: {MyGame.Web.Auth, :verify}
end

defmodule MyGame.Web.WorldChannel do
  use Cauldron.Net.Channel,
    game: MyGame.Client,
    drawer: {Cauldron2D.Net.Drawer, sheet_url: "/play/atlas.png"},
    audio: %{rate: 22_050, channels: 1}
end
```

`use Cauldron.Net.Socket` takes `:channel` and `:verify` (a `{module, function}` given the
connect params, answering `{:ok, assigns}` or `:error`). The assigns carry `:username`
and, when the game keeps them, `:settings`. `:topic` renames the prefix, default
`"world"`. `voice: true` also routes the `"voice"` topic.

`use Cauldron.Net.Channel` takes `:game` (a `Cauldron.Client.Game`), `:drawer` (a
`Cauldron.Net.Drawer`, a module or `{module, opts}`), `:topic` and `:audio`, the PCM
format a browser gets when it asks for none.

| Topic | What it runs |
| --- | --- |
| `world:<id>` | The world `id`, as the game's `worlds/1` lists it |
| `front:title` | A title the game draws itself (`Cauldron.Front`) |
| `chat:lobby` | The lobby's room, in a game with a chat |
| `voice` | Voice calls, when the socket has `voice: true` |

The join params reach the game's `join_props/1` as `:params`. A `"saved"` param is the
player's settings as a previous `"settings"` push signed them; `"audio"`,
`%{"rate" => hertz, "channels" => 1 | 2}`, is the PCM format the browser wants, and
`false` asks for no sound. `"preset"`, `"fps"` and `"pointer"` are the player's settings
beside the world.

From the browser the channel reads input and hands it to the session:

| Message | Payload | Goes to |
| --- | --- | --- |
| `"key"` | `key`, `mods`, `down` | `Cauldron.Net.Session.key/4` |
| `"mouse"` | `button`/`wheel`/`move` and `at` | `Cauldron.Net.Session.mouse/2` |
| `"pane"` | `columns`, `rows` | `Cauldron.Net.Session.pane/2` |
| `"hold"` | `action`, `down`, `strength` | `Cauldron.Net.Session.hold/4` |
| `"padline"` | A `Gamepad.Wire` line | `Cauldron.Net.Session.pad_event/2` |
| `"aim"` | `at`, a world point or `null` | `Cauldron.Net.Session.aim/2` |
| `"pan"` | `x`, `y`, fractions of the pane | `Cauldron.Net.Session.pan/2` |
| `"recentre"` | none | `Cauldron.Net.Session.recentre/1` |
| `"configure"` | `preset`, `pointer`, `fps` | `Cauldron.Net.Session.configure/2` |
| `"levels"` | `sfx`, `music` | `Cauldron.Net.Session.levels/3` |
| `"say"` | `text` | `Cauldron.Net.Session.say/2` |

Keys go up as well as down, so a held action is let go when the key is. The channel also
answers `"music"`, `"pause"` and the game's menu. When the round is over and the game has
a summary, the channel leaves the world, pushes `"front"` and runs the summary instead.

## Sessions

A session is a struct and functions, so a process can drive it without a channel. A
channel is that process.

```elixir
{:ok, session, pushes} =
  Cauldron.Net.Session.join(
    MyGame.Client,
    world,
    "alice",
    %{settings: %{sfx: 0.8, music: 0.3}},
    drawer: Cauldron2D.Net.Drawer,
    audio: %{rate: 22_050, channels: 1}
  )

{session, more} = Cauldron.Net.Session.frame(session, message)
```

`Cauldron.Net.Session.join/5` gives the player a place in `world`. A world given as
`{module, opts}` is the player's own, started here and stopped by `leave/1`.

| Option | What it is |
| --- | --- |
| `:drawer` | The drawer, required |
| `:audio` | A PCM format, or `:off` |
| `:sink` | A `Cauldron.Audio.Sink` instead of the process sink |
| `:policy` | A sound policy instead of `Cauldron.Net.Audio.policy/0` |
| `:local` | `true` for a client in this node: payloads are terms |
| `:gpu` | `true` for an in-node client that draws the scene's `:gpu` itself |
| `:chat_room` | The `Cauldron.Chat` room the player talks in |

A frame returns the pushes in order: the `"status"`, the drawer's scene, and once
`"ended"` with the outcome and last view. `Cauldron.Net.Session.changed/2` answers a
message for the drawer, such as the game's art changing.

## Links

A link carries one player, or a whole server world, into an Elixir program.

| Module | What it connects to |
| --- | --- |
| `Cauldron.Net.Link.Socket` | A server over its WebSocket; one player |
| `Cauldron.Net.Link.Local` | A world process in this node or a connected one; one player |
| `Cauldron.Net.Link.World` | A server's world, standing in for it; a socket per player |

`Cauldron.Net.Link.World` is what a game uses to join a world it does not run. It stands in
for a `Cauldron.World` to `Cauldron.Player`, so the game plays against it as against a local world:

```elixir
{:ok, token} = Cauldron.Net.Remote.login("http://arcade:2280/api", "alice", "secret", false)

{:ok, world} =
  Cauldron.Net.Link.World.start(
    url: "http://arcade:2280",
    token: token,
    world: "pit",
    drawer: {Cauldron2D.Net.Drawer, sheet_url: "/atlas.png"}
  )

:ok = Cauldron.Player.join(world, "alice", %{username: "alice"})
```

A player's remote view is `%{remote: remote, world: name}`. `remote` holds the latest status,
the round's end and what the drawer keeps of each scene. The game draws it and reads the
hud with `Cauldron.Net.Link.World.hud/1`, the outcome with `outcome/1`; when the
connection ends the player gets one last view with `closed: reason`.

A link reports to its `:owner` as `{:cauldron_link, ...}` messages: `:joined` or
`:refused`, `:audio`, each tick's `:status`, `:go`, `:settings`, `:clipboard`, `:ended`,
`:pcm` and `:closed`, plus the drawer's own. `key/4`, `mouse/2`, `pad_event/2`, `hold/4`,
`aim/2`, `pane/2`, `pan/2`, `configure/2`, `say/2`, `levels/3` and `pause/1` are what the
player does. A local link also carries chat, `rest/1` and `wake/1` for an app in the
background.

## The wire

`Cauldron.Net.Wire` is the Phoenix channel protocol (serializer 2.0.0) as an Elixir
client speaks it, and the session's own pushes read into plain shapes.

```elixir
payload = %{"hud" => [], "over" => nil, "subject" => nil, "focus" => nil}
Cauldron.Net.Wire.status(payload)
```

`encode/5` gives a text frame. `decode/1` reads one, and `decode_binary/1` a binary push.
`status/1` gives the hud rows, the outcome, the subject and the focus; `go/1` gives
`:lobby`, `:settings` or `:title`; `field/2` reads a payload by atom key or by its text key
for a payload decoded from JSON. A drawer's pushes are its own to read.

## The drawer

A drawer is what a client is sent to show a scene, and what a client makes of it. It is
named with `:drawer` wherever a session or a link starts, as a module or
`{module, opts}`. Session options reach `open/2` with the drawer's own, and a channel adds
`:params`, the client's join params.

| Callback | When it is called |
| --- | --- |
| `open/2` | A session starts; gives the drawer's state and its first pushes |
| `draw/2` | Each scene, from the props the game's view drew it with |
| `pane/2` | The client's pane, `{columns, rows}` at zoom 1 |
| `world_at/3` | The world point under the pointer, or `nil` |
| `changed/3` | A message the session received and did not know |
| `colour/1` | The RGB a hud name stands for |
| `close/2` | The session leaves; subscriptions end |
| `local/2` | A push for a client in this node, as `{:cauldron_link, ...}` messages |
| `reader/1` | A socket link starts its reader |
| `read/4` | A push the socket link received |
| `remote/2` | A reader's message kept in a link world's `remote` map |
| `browser/0` | Optional: scripts, head HTML and join params for a browser |

The behaviour asks for all of them but `browser/0`. A drawer that serves only browsers
implements the server side and answers `:unknown` or `[]` on the client side; one that
also serves Elixir clients implements `local/2` or `reader/1`, `read/4` and `remote/2`.

Every callback that has something for the client returns pushes, `{event, payload}`
pairs. A push is sent to the browser as it is; a binary payload becomes a binary push.

A front end supplies the drawer, the socket module, the channel module, and a web server
that routes the socket. It need not supply pages: a browser page is the front end's, above
the channel, and `cauldron_2d_net` has those pages.

## The sound policy

Sound is the server's cost, and `Cauldron.Net.Audio` decides what a session's sound
costs.

```elixir
Cauldron.Net.Audio.set(music: :world, sfx: :personal, rate: 22_050)
Cauldron.Net.Audio.policy()
```

| Music | What each session does |
| --- | --- |
| `:personal` | Synthesises its own, cued by its own view. The default |
| `:world` | One stage a world (`Cauldron.Net.Audio.Shared`), mixed under each session's effects |
| `:static` | Plays the first section it is cued, rendered once and looped |
| `:dynamic` | Personal, at a rate the node's load sets: 44 100 Hz under 30% busy, 22 050 Hz past 60% |
| `:off` | No music |

`:sfx` is `:personal` or `:off`. `:rate` caps what any session gets; one that asks for less
gets what it asked. `Cauldron.Net.Audio.format/1` answers what a session gets for what it
asked; `subscribe/0` tells the calling process `{:cauldron_audio_rate, rate}` when the rate
changes.

The channel sends the result as binary `"pcm"` pushes. `Cauldron.Net.Sound` plays what a
socket link delivers through this machine's speaker, in a process of its own:

```elixir
{:ok, sound} = Cauldron.Net.Sound.start_link(rate: 22_050, channels: 1)
:ok = Cauldron.Net.Sound.play(sound, chunk)
```

## The HTTP API, and nodes

`Cauldron.Net.Api` is a plug a game forwards a path to. It answers clients on other
machines over plain HTTP.

```elixir
forward "/api", Cauldron.Net.Api,
  login: &MyGame.Web.Auth.login/2, token: &MyGame.Web.Auth.token/1, ledger: MyGame.Ledger
```

| Route | Answers |
| --- | --- |
| `POST /token` | A token for a name and password; `register: true` makes the account |
| `GET /worlds` | The worlds a lobby lists (`Cauldron.Worlds.list/0`) |
| `GET /stats` | How the server is keeping up |
| `GET /leaders` | The boards, when the game keeps a ledger |

`Cauldron.Net.Remote` calls that API from a client: `login/4`, `worlds/1`, `stats/1`,
`leaders/4`. To a node this VM is connected to, it offers `node_worlds/1`, `node_world/2`
and `node_leaders/5`.

`Cauldron.Net.Remote.Worlds` names a world that is not in this VM, so a player joins it as
any other world: `{:via, Cauldron.Net.Remote.Worlds, {:node, node, id}}` or
`{:url, url, token, id, opts}`.

## Voice

Voice is off until the game opens it. It is calls between browser players, over WebRTC
when it can and through the channel when it cannot.

```elixir
Cauldron.Net.Voice.open(relay: true, stun: ["stun:stun.example.org"], wait: 5_000)
Cauldron.Net.Voice.call("alice", "bob")
Cauldron.Net.Voice.state("alice")
```

`:relay` lets a call fall back to the server's channel, `:stun` and `:turn` name the
servers that help a direct route, and `:wait` is how long a call waits for one. A call
needs both players: `call/2`, then `accept/2` or `decline/2`. `hang_up/2` ends it and
`mute/2` turns a microphone off. `Cauldron.Net.Voice.Channel` is joined by a browser whose
socket has `voice: true`; a page that serves `voice.js` gets `window.cauldronVoice`.

## Load

`Cauldron.Net.Load` tests a running server over the wire: players and watchers join its
worlds, their frames are measured against the server's ticks, and the server's `/stats`
is read alongside.

```elixir
Cauldron.Net.Load.run(url: "http://arcade:2280/api", actions: ["fire"], players: 40, seconds: 60)
```

`:ramp` adds sessions at each report until the run degrades, and `:out` writes every
report to a file as JSON. `stop/0` ends a run early from another process.

## Where to go next

| You want to | Read |
| --- | --- |
| Understand the world a channel joins | [Worlds and players](https://hexdocs.pm/cauldron_core/worlds-and-players.html) |
| Add sound to a game | [Sound and music](https://hexdocs.pm/cauldron_core/sound-and-music.html) |
| Serve a 2D game to a browser | [`Cauldron2D.Net.Serve`](https://hexdocs.pm/cauldron_2d_net/Cauldron2D.Net.Serve.html) |
| Read the 2D drawer | [`Cauldron2D.Net.Drawer`](https://hexdocs.pm/cauldron_2d_net/Cauldron2D.Net.Drawer.html) |
| Serve a 3D scene | [3D in a browser](https://hexdocs.pm/cauldron_3d_net/browser-3d.html) |
