# Cauldron3D.Net

Cauldron3D.Net shows 3D scenes in the browser. A scene server takes the same changes
`CauldronGPU.submit/2` takes and keeps the scene. It broadcasts each tick as
`CauldronGPU.Stream` bytes over a Phoenix channel. In the browser, `cauldron3d.js` draws
them with three.js.

```elixir
defmodule MyGame.Web.SceneSocket do
  use Cauldron3D.Net.Socket, channel: MyGame.Web.SceneChannel
end

defmodule MyGame.Web.SceneChannel do
  use Cauldron3D.Net.Channel
end

defmodule MyGame.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_game
  socket "/socket", MyGame.Web.SceneSocket, websocket: true, longpoll: false
  plug Cauldron3D.Net.Page, scene: "courtyard"
end

{:ok, scene} = Cauldron3D.Net.Scene.open(id: "courtyard", events: self())
cube = Cauldron3D.Net.Scene.mesh(scene, CauldronGPU.Mesh.cube(1.0))
Cauldron3D.Net.Scene.submit(scene, [{:instance, 1, %CauldronGPU.Instance{mesh: cube}}])
```

`Cauldron3D.Net.Scene.open/1` starts a scene linked to the caller; under a supervisor use
`start_link/1` and find the scene with `Cauldron3D.Net.Scene.lookup/1`. A scene is a
`CauldronGPU.Target`, so the `cauldron_gpu` converters (`CauldronGPU.Bsp.upload/4` and the
rest) and any code written against `CauldronGPU.Target` upload to it as to a renderer.

A browser joining late gets the whole scene, then every tick. Its keyboard, mouse,
resize and focus events reach the `:events` pid as
`{:cauldron_3d_net, scene_id, session, event}`, in the shapes `CauldronGPU`'s windows send.

## Installation

```elixir
def deps do
  [
    {:cauldron_3d_net, "~> 0.3"},
    {:bandit, "~> 1.5"}
  ]
end
```

Your endpoint needs `pubsub_server: Cauldron3D.Net.PubSub` (the package starts it) and a
web server adapter such as Bandit. The page loads three.js from jsDelivr, so the browser
needs to reach it.

## Examples

* `mix run examples/showcase.exs` serves the cauldron_gpu showcase at
  http://localhost:4400/; arrow keys or W A S D in the browser move the camera.
* `mix run examples/quake_map.exs ~/quake e1m1` serves a Quake map with its sky.

## What the browser draws

The browser draws what WebGL 2 can:

* physically based materials, with vertex colours, add and multiply blending, scrolling,
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

Its bloom is stronger than the native renderer's. The browser ignores ray-traced effects,
upscaling and frame generation.
