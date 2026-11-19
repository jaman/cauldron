# 3D in Livebook

`cauldron_3d_kino` puts a 3D scene in a Livebook cell. The cell's process keeps the
scene; the browser showing the notebook draws it with three.js on the viewer's graphics
card. The machine running the notebook draws nothing and sends only the changes.

A view is also a `Cauldron3D.Scene.Target`, so code written for a native renderer or a
browser scene uploads to it unchanged.

## Installing

```elixir
Mix.install([
  {:cauldron_3d_kino, "~> 0.4"}
])
```

The cell loads three.js from jsDelivr, so the browser needs to reach it. Nothing else is
needed on the machine running the notebook.

## The cell

A view starts empty. Evaluating it shows the cell, black until something is in it.

```elixir
view = Cauldron3D.Kino.new(height: 420)
```

`new/1` takes `:height`, the cell's height in pixels, default 480. The last expression of
a cell must be the view for Livebook to render it; keep `view` at the end, or return it
from the cell.

## What it renders with

The cell runs `cauldron_3d_net`'s browser client (`cauldron3d.js`) as a Kino asset.
`Cauldron3D.Kino.Client.source/0` points its three.js imports at jsDelivr's `+esm` builds.
`Cauldron3D.Kino.Client.path/0` is the client in `cauldron_3d_net`, and `rewrite/2` is the
import rewrite, for a front end of your own.

Opening the notebook gives the browser the whole scene as a snapshot. Each later
`submit/2` goes out as a `Cauldron3D.Scene.Stream` batch, which the client applies. It
draws what the browser client draws:

* physically based materials, lights and the directional light's shadows
* fog, skies, bloom, tone mapping and coloured light styles
* 2D layers over the scene or on their own
* poses, skinned on the browser's CPU, and interpolation between ticks

Ray-traced effects, upscaling and frame generation are native-renderer features and are
ignored. The full list is in [3D in a browser](https://hexdocs.pm/cauldron_3d_net/browser-3d.html).

## Building a scene

Upload a mesh, texture or material once and get a handle back. One `submit/2` is one
tick: everything in the list changes at once.

```elixir
alias Cauldron3D.Scene.{Camera, Environment, Instance, Light, Material, Mesh, Quat, Texture, Transform}

view = Cauldron3D.Kino.new(height: 420)

checker =
  Cauldron3D.Kino.texture(
    view,
    Texture.checker(256, 8, {200, 200, 190, 255}, {70, 75, 80, 255})
  )

plane = Cauldron3D.Kino.mesh(view, Mesh.plane(20, 5))
cube = Cauldron3D.Kino.mesh(view, Mesh.cube(1.0))
sphere = Cauldron3D.Kino.mesh(view, Mesh.sphere(0.8, 32))

floor = Cauldron3D.Kino.material(view, %Material{base_texture: checker, roughness: 0.4})

gold =
  Cauldron3D.Kino.material(view, %Material{
    base_color: {1.0, 0.78, 0.34, 1.0},
    metallic: 1.0,
    roughness: 0.25
  })

Cauldron3D.Kino.submit(view, [
  %Environment{ambient_intensity: 0.25, exposure: 1.1, shadow_distance: 20.0},
  {:instance, 1, %Instance{mesh: plane, materials: [floor]}},
  {:instance, 2,
   %Instance{
     mesh: sphere,
     materials: [gold],
     transform: Transform.new(position: {-1.6, 0.8, 0.0})
   }},
  {:instance, 3,
   %Instance{
     mesh: cube,
     materials: [gold],
     transform: Transform.new(position: {1.6, 0.5, 0.0})
   }},
  {:light, 1,
   %Light{
     kind: :directional,
     direction: {-0.5, -1.0, -0.35},
     color: {1.0, 0.95, 0.85},
     intensity: 3.0,
     shadows: true
   }},
  %Camera{position: {0.0, 2.0, 6.0}, rotation: Quat.yaw_pitch(0.0, -0.25), fov_y: 1.0}
])

view
```

| Function | What it does |
| --- | --- |
| `submit/2` | One tick of changes, sent to every browser showing the view |
| `mesh/2`, `texture/2`, `canvas/2` | Uploads an asset and gives its handle |
| `material/2`, `scatter/2` | Defines one and gives its handle |
| `release/2` | Lets the view drop an asset once nothing uses it |
| `subscribe/1`, `unsubscribe/2` | Input to a process |
| `events/1` | Input as a stream of `{client, event}` |

## Driving the camera

A camera is a change like any other. Submitting a new `%Cauldron3D.Scene.Camera{}` moves
the view; the browser draws the next batch with it.

```elixir
Cauldron3D.Kino.submit(view, [
  %Camera{position: {0.0, 2.0, 6.0}, rotation: Quat.yaw_pitch(0.0, -0.25), fov_y: 1.0}
])
```

For a camera the viewer moves, read the cell's input. Input arrives as the events a
native window sends: mouse buttons and motion, the wheel, keys, resize and focus. They
are the same shapes `Cauldron3D.Net.Events` decodes, through
`Cauldron3D.Kino.events/1`.

The notebook's orbit keeps the camera's yaw, pitch and distance, and turns them into a
`Camera`:

```elixir
alias Cauldron3D.Scene.{Camera, Quat}

defmodule Orbit do
  defstruct yaw: 0.0, pitch: -0.25, distance: 6.3, dragging: false

  def handle(orbit, {:mouse_button, :down, 1, _x, _y}), do: %{orbit | dragging: true}
  def handle(orbit, {:mouse_button, :up, 1, _x, _y}), do: %{orbit | dragging: false}

  def handle(%{dragging: true} = orbit, {:mouse_motion, _x, _y, dx, dy}),
    do: %{orbit | yaw: orbit.yaw - dx * 0.01, pitch: clamp(orbit.pitch - dy * 0.01, -1.4, -0.05)}

  def handle(orbit, {:mouse_wheel, _dx, dy}),
    do: %{orbit | distance: clamp(orbit.distance - dy, 2.0, 15.0)}

  def handle(orbit, _event), do: orbit

  def camera(orbit) do
    rotation = Quat.yaw_pitch(orbit.yaw, orbit.pitch)
    {x, y, z} = Quat.rotate(rotation, {0.0, 0.0, orbit.distance})
    %Camera{position: {x, y + 0.5, z}, rotation: rotation, fov_y: 1.0}
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
```

`Kino.listen/3` reads the view's events in the background, keeps the orbit between them,
and sends a new camera when it moves:

```elixir
view
|> Cauldron3D.Kino.events()
|> Kino.listen(%Orbit{}, fn {_client, event}, orbit ->
  moved = Orbit.handle(orbit, event)

  if moved != orbit do
    Cauldron3D.Kino.submit(view, [Orbit.camera(moved)])
  end

  {:cont, moved}
end)
```

`subscribe/1` is the same without `Kino.listen`: it sends the calling process
`{:cauldron_3d_kino, ref, client, event}` until `unsubscribe/2` or the process exits.
`events/1` is built on it.

## Animating a scene

`Kino.listen/2` runs a function every so many milliseconds. Each run submits one tick;
the browser blends between ticks, so a thing turns smoothly at the display's rate.

```elixir
Kino.listen(50, fn tick ->
  Cauldron3D.Kino.submit(view, [
    {:instance, 3,
     %Instance{
       mesh: cube,
       materials: [gold],
       transform:
         Transform.new(
           position: {1.6, 0.5, 0.0},
           rotation: Quat.axis_angle({0.3, 1.0, 0.2}, tick * 0.05)
         )
     }}
  ])
end)
```

## Loading a scene built elsewhere

A view is a `Cauldron3D.Scene.Target`, so the `cauldron_gpu` converters and the scene
modules of the examples upload to it as to a native renderer. A scene written against
`Cauldron3D.Scene.Target` needs one `submit/2` of what it uploaded and one camera.

The notebook `notebooks/scene.livemd` in the package builds a lit scene, turns a cube from
a background loop and orbits the camera. The courtyard example shows loading glTF scenes
into a view with `cauldron_3d_formats`.

A large scene is sent once and kept. A detailed scene's textures and meshes can be tens
or hundreds of megabytes, so the first render of the cell waits for the browser to receive
them. Later ticks send only what changed.

## Where to go next

| You want to | Read |
| --- | --- |
| Serve a scene to a page | [3D in a browser](https://hexdocs.pm/cauldron_3d_net/browser-3d.html) |
| Understand the changes | [`Cauldron3D.Scene.Stream`](https://hexdocs.pm/cauldron_3d_scene/Cauldron3D.Scene.Stream.html) |
| Upload to a view as to a renderer | [`Cauldron3D.Scene.Target`](https://hexdocs.pm/cauldron_3d_scene/Cauldron3D.Scene.Target.html) |
| Draw with the graphics card natively | [`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu/CauldronGPU.html) |
