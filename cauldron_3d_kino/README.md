# Cauldron3D.Kino

Cauldron3D.Kino shows a 3D scene in a Livebook cell. The cell's process keeps the scene.
The browser showing the notebook draws it with three.js on its own graphics card. The
machine running the notebook draws nothing.

```elixir
view = Cauldron3D.Kino.new(height: 420)
cube = Cauldron3D.Kino.mesh(view, Cauldron3D.Scene.Mesh.cube(1.0))

Cauldron3D.Kino.submit(view, [
  {:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube}},
  %Cauldron3D.Scene.Camera{position: {0.0, 1.0, 4.0}}
])

view
```

A view is a `Cauldron3D.Scene.Target`, so the `cauldron_gpu` converters and any code written
against `Cauldron3D.Scene.Target` upload to it as they do to a native renderer. Input on the
cell comes back as `CauldronGPU` window events, through `Cauldron3D.Kino.events/1` (a
stream for `Kino.listen/3`) or `Cauldron3D.Kino.subscribe/1`.

## Installation

```elixir
Mix.install([
  {:cauldron_3d_kino, "~> 0.3"}
])
```

The cell loads three.js from jsDelivr, so the browser needs to reach it.

## What the browser draws

The cell runs `cauldron_3d_net`'s client, so it draws what that client draws: physically
based materials, point, spot and directional lights with the directional light's shadows,
fog, skies, bloom, 2D layers and the rest listed in `cauldron_3d_net`'s README. Ray-traced
effects, upscaling and frame generation are native-renderer features and are ignored.

## Notebook

`notebooks/scene.livemd` builds a lit scene, turns a cube from a background loop and
orbits the camera with the mouse.

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
