# 3D in a browser

`cauldron_3d_net` serves a 3D scene to a browser. A scene server keeps the scene as
`Cauldron3D.Scene.Stream` changes, broadcasts each tick over a Phoenix channel, and
`cauldron3d.js` draws those changes with three.js on the browser's graphics card. The
machine serving the scene draws nothing.

This is the smaller use of the package: one scene, one page, no game. For a 3D game
played over `Cauldron.Net` sessions, see [3D games over the network](#3d-games-over-the-network).

## Opening a scene

A scene is a process with an id. It keeps everything sent to it, so a browser that joins
late gets the whole scene, then every tick.

```elixir
{:ok, scene} = Cauldron3D.Net.Scene.open(id: "courtyard", events: self())

cube = Cauldron3D.Net.Scene.mesh(scene, Cauldron3D.Scene.Mesh.cube(1.0))

Cauldron3D.Net.Scene.submit(scene, [
  {:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube}},
  %Cauldron3D.Scene.Camera{position: {0.0, 1.0, 4.0}}
])
```

`open/1` starts the scene linked to the caller. Under a supervisor, use `start_link/1`,
and find the started scene with `lookup/1`. Options are `:id` (a string, required) and
`:events` (a pid that receives browser input).

| Function | What it does |
| --- | --- |
| `mesh/2`, `texture/2`, `canvas/2` | Uploads an asset and gives its handle |
| `material/2`, `scatter/2` | Defines one and gives its handle |
| `submit/2` | Sends one tick of changes to every watching browser and keeps them |
| `release/2` | Lets the scene drop an asset once nothing uses it |
| `snapshot/1` | The bytes that give a browser the whole scene |
| `event/3` | Passes a browser's event to the scene's `:events` pid |
| `topic/1` | The PubSub topic a scene's batches are broadcast on |

A scene is a `Cauldron3D.Scene.Target`, so the `cauldron_gpu` converters
(`Cauldron3D.Scene.Bsp.upload/4` and the rest) and any code written against the
protocol upload to it as to a native renderer. What the browser draws is what WebGL 2
can draw.

## The socket and the channel

The socket carries browsers in; the channel is where they watch a scene.

```elixir
defmodule MyGame.Web.SceneSocket do
  use Cauldron3D.Net.Socket, channel: MyGame.Web.SceneChannel
end

defmodule MyGame.Web.SceneChannel do
  use Cauldron3D.Net.Channel
end
```

`use Cauldron3D.Net.Socket` takes `:channel`, `:topic` (the prefix, default `"scene"`) and
an optional `:verify`, a `{module, function}` given the connect params and answering
`{:ok, assigns}` or `:error`. Without one, everyone may connect.

`use Cauldron3D.Net.Channel` takes `:topic` and defines a channel on `"scene:<id>"`, `id`
a scene started with `start_link/1`. Joining a scene that does not exist is refused. On
joining, the channel pushes the whole scene as one binary `"changes"` message and then
each batch the scene broadcasts. Its `"event"` messages are decoded by
`Cauldron3D.Net.Events` and passed to the scene.

A browser's input reaches the `:events` pid as
`{:cauldron_3d_net, scene_id, session, event}`. `session` is a reference for that browser,
and `event` is shaped as `CauldronGPU`'s window events, plus `:joined` when the browser
arrives and `:left` when it goes.

| Event | Shape |
| --- | --- |
| Key | `{:key, action, key, repeat?}`, `action` is `:down` or `:up` |
| Mouse motion | `{:mouse_motion, x, y, dx, dy}` |
| Mouse button | `{:mouse_button, action, button, x, y}`, `action` is `:down` or `:up` |
| Wheel | `{:mouse_wheel, dx, dy}` |
| Resize | `{:resized, width, height}` |
| Focus | `{:focus, focused?}` |

## The endpoint

The endpoint needs `pubsub_server: Cauldron3D.Net.PubSub`. The package starts that PubSub
server.

```elixir
defmodule MyGame.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_game

  socket "/socket", MyGame.Web.SceneSocket, websocket: true, longpoll: false
  plug Cauldron3D.Net.Page, scene: "courtyard", title: "Courtyard"
end
```

```elixir
config :my_game, MyGame.Web.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [port: 4400],
  server: true,
  secret_key_base: "...",
  pubsub_server: Cauldron3D.Net.PubSub
```

The package needs a web server adapter; Bandit is the one its examples use. The page loads
three.js from jsDelivr, so the browser needs to reach the CDN.

## Serving the page

`Cauldron3D.Net.Page` is a plug that serves one scene and the scripts it needs:

| Path | What it serves |
| --- | --- |
| `GET /` | The page, filling the window |
| `GET /cauldron3d.js` | The browser client |
| `GET /phoenix.min.js` | Phoenix's socket client |
| `GET /favicon.ico` | Nothing, with a 204 |

Its options are `:scene` (required), `:socket` (default `"/socket"`), `:topic` (default
`"scene"`) and `:title`. At the endpoint root it serves the whole site. Under a path, use
`forward`:

```elixir
forward "/watch", to: Cauldron3D.Net.Page,
  init_opts: [scene: "courtyard", socket: "/socket", title: "Courtyard"]
```

The page writes an import map for three.js at the version
`Cauldron3D.Net.Page.three_version/0` names, loads `phoenix.min.js`, then calls
`start(canvas, %{scene: id, socket: path, topic: prefix})` from `cauldron3d.js`. The
canvas fills the window and takes keyboard focus.

## What the browser draws

`cauldron3d.js` opens a socket, joins `"scene:<id>"`, applies the snapshot, and applies
each `"changes"` message as it arrives. The changes are the same `Cauldron3D.Scene.Stream`
bytes a native renderer takes: uploads, releases and one tick's places.

The browser draws what WebGL 2 can:

* physically based materials, vertex colours, add and multiply blending, scrolling,
  reflection-mapped and rippling textures, and the shimmer (`smear`)
* point, spot and directional lights, and the directional light's shadows
* fog, the sky and sky pictures, and coloured light styles
* the overlay and screen tint, bloom and tone mapping
* 2D layers: sprites and column layers into the frame or into canvases, over the 3D
  scene or alone when no camera has been sent
* display-space lighting with light tables, gamma, contrast and brightness
* camera viewports and low-detail resolution
* swelling shells, and instances drawn in front, without the depth test or standing in
  a room
* poses, blended and skinned on the browser's CPU, and interpolation between ticks

Its bloom is stronger than the native renderer's. It ignores ray-traced effects,
upscaling and frame generation, which are native-renderer features.

## 3D games over the network

A 3D game played over `Cauldron.Net` sessions, the way 2D games are, names
`Cauldron3D.Net.Drawer` as its drawer:

```elixir
use Cauldron.Net.Channel, game: MyGame.Client, drawer: Cauldron3D.Net.Drawer
```

Each client is sent its scene as the changes a renderer takes and draws it itself. The
game's scene gives the drawer a `:gpu` closure,
`fn target, cache, {width, height}, aspect -> {changes, cache} end`, and optionally
`:gpu_size`. For each client the drawer keeps an outbox (`Cauldron3D.Net.Outbox`) the
closure uploads to, so a client joining later is given the whole scene and uploads the
game makes in the background reach it as they finish.

The drawer pushes `{"changes", payload}`. A browser joins with the param
`"changes" => "stream"` and reads `Cauldron3D.Scene.Stream` bytes; any other client reads
the change terms, keeps them with `Cauldron3D.Net.RemoteScene` and draws them with
`Cauldron3D.Net.Replay`; a client in the same node gets the terms themselves. The game's
scene function decides:

```elixir
def scene(%{remote: _} = view, _look), do: Cauldron3D.Net.RemoteScene.scene(view)
```

The drawer's `browser/0` gives the game's pages the two scripts and the import map they
need, which is why a game's browser page can be served by `cauldron_2d_net`'s pages with
`drawer: Cauldron3D.Net.Drawer`.

## Where to go next

| You want to | Read |
| --- | --- |
| Understand the scene changes | [`Cauldron3D.Scene.Stream`](https://hexdocs.pm/cauldron_3d_scene/Cauldron3D.Scene.Stream.html) |
| Upload to a scene as to a renderer | [`Cauldron3D.Scene.Target`](https://hexdocs.pm/cauldron_3d_scene/Cauldron3D.Scene.Target.html) |
| Draw with the graphics card natively | [`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu/CauldronGPU.html) |
| Show a scene in a notebook | [3D in Livebook](https://hexdocs.pm/cauldron_3d_kino/livebook.html) |
| Carry a world over the network | [Networking](https://hexdocs.pm/cauldron_net/networking.html) |
