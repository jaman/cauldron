# CauldronGPU

3D scenes and 2D sprite layers drawn by the graphics card, described from Elixir. Your
code keeps the game world and sends the renderer what changed each tick; a native render
thread draws at the display's rate from its own copy of the scene, moving things smoothly
between your ticks.

The same scene can go to a window, to an offscreen picture you read back (and show in a
terminal), to a renderer in its own OS process, or to browsers (`cauldron_3d_net`).

* **Metal** runs on macOS. It draws with deferred lighting, cascaded shadows,
  transparency and bloom. It also has ray-traced shadows, ambient occlusion,
  reflections and one-bounce global illumination, and MetalFX upscaling and frame
  generation.
* **Vulkan** runs on Linux and Windows, and on macOS through MoltenVK. It is the same
  renderer.

## Installation

```elixir
def deps do
  [{:cauldron_gpu, "~> 0.3"}]
end
```

The package always compiles. The native renderer is built when what it needs is on the
machine; without it, `CauldronGPU.backends/0` answers `[]`, `CauldronGPU.open/1` answers
`{:error, reason}`, and games draw in software. To set the renderer up, run:

```sh
mix cauldron_gpu.setup
```

It looks for what the build needs in the platform's usual places, offers to install what
is missing (showing what it will run), builds the renderer and opens the graphics card to
check it. Declining leaves software drawing; running it again starts over. `--check`
only reports, `--yes` accepts everything, and `--software` builds no renderer.

| Platform | What the build needs | What the setup installs |
| --- | --- | --- |
| macOS | Apple's command-line tools, SDL3 and `pkg-config`; for the Vulkan backend, Vulkan's loader and headers and MoltenVK | the command-line tools through Apple's installer, the rest through Homebrew (and Homebrew itself) |
| Linux | a C++20 compiler, `make`, `pkg-config`, SDL3, Vulkan's headers, and a Vulkan driver to run it | packages through apt, dnf, pacman or zypper with `sudo`; Vulkan's headers by download; SDL3 built from source where the distribution has none |
| Windows | MSVC's C++ Build Tools, SDL3's development files, Vulkan's headers, and a Vulkan driver | MSVC through `winget`; SDL3 and Vulkan's headers by download, with no administrator rights |

The renderer loads Vulkan from the graphics driver when it runs, so only Vulkan's headers
are needed to build it, not LunarG's SDK. Downloads go into
`:filename.basedir(:user_cache, "cauldron_gpu")`, and the paths found are kept in
`build.config` under `:filename.basedir(:user_config, "cauldron_gpu")`, which later builds
read (`CauldronGPU.Setup`). Environment variables set by hand take precedence: `SDL3_DIR`,
`VULKAN_INCLUDE` (or `VULKAN_SDK`), `PKG_CONFIG` and `PKG_CONFIG_PATH`.

Shaders come compiled in `priv/shaders`; `make shaders` rebuilds them after a change in
`shaders/`, which needs the Slang compiler (`make slang`) and, for Metal, Xcode.

On macOS the Metal backend is always built, and Vulkan beside it when Vulkan is found.
Metal is used first on a Mac; Vulkan there runs the same path as Linux and Windows. Set
`CAULDRON_GPU_VULKAN=0` to leave Vulkan out.

## A first scene

```elixir
alias Cauldron3D.Scene.{Camera, Instance, Light, Material, Mesh, Transform}

{:ok, gpu} = CauldronGPU.open(title: "Hello", width: 1280, height: 720)

cube = CauldronGPU.mesh(gpu, Mesh.cube(1.0))
floor = CauldronGPU.mesh(gpu, Mesh.plane(20, 4))
red = CauldronGPU.material(gpu, %Material{base_color: {0.8, 0.1, 0.1, 1.0}, roughness: 0.4})
grey = CauldronGPU.material(gpu, %Material{base_color: {0.5, 0.5, 0.5, 1.0}})

CauldronGPU.submit(gpu, [
  {:instance, 1, %Instance{mesh: floor, materials: [grey]}},
  {:instance, 2, %Instance{mesh: cube, materials: [red], transform: Transform.new(position: {0.0, 0.5, 0.0})}},
  {:light, 1, %Light{kind: :directional, direction: {-0.4, -1.0, -0.3}, intensity: 3.0, shadows: true}},
  %Camera{position: {0.0, 1.5, 4.0}}
])
```

Then, once a tick (say 30 times a second), send what moved:

```elixir
CauldronGPU.submit(gpu, [
  {:move, 2, Transform.new(position: {x, 0.5, 0.0})},
  %Camera{position: eye, rotation: Cauldron3D.Scene.Quat.yaw_pitch(yaw, pitch)}
])
```

Window events arrive at the process that opened it (or the `:events` pid) as
`{:cauldron_gpu, window_id, event}`: keys (`{:key, :down | :up, key, repeat?}`), mouse
motion, buttons and wheel, resizes, focus and `:close_requested`.
`CauldronGPU.relative_mouse/2` hides the pointer for mouse look.

## How a scene works

The structs, the change stream, `Cauldron3D.Scene.Target` and the game converters are in the
`cauldron_3d_scene` package, which this package depends on. Code that only describes
scenes, such as a browser or Livebook client, can depend on `cauldron_3d_scene` alone
and never builds the renderer.

* **Resources** — meshes, textures and materials are uploaded once and answered with a
  `Cauldron3D.Scene.Handle`. Upload through `CauldronGPU.mesh/2`, `texture/2` and `material/2`
  (or `Cauldron3D.Scene.Target` for code that should work with every kind of renderer).
  Putting a mesh or texture again under a handle's id replaces it
  (`{:mesh, handle.id, mesh}` in a submit), which is how per-tick meshes such as
  particles or a HUD texture are updated.
* **Changes** — everything else is a list of changes, `Cauldron3D.Scene.Stream` lists them all:
  instances, moves, poses for animated models, lights, the camera, the environment, light
  styles, the overlay picture, the screen tint and effects. Ids are yours; an id put again
  replaces what it named.
* **Ticks** — each `submit/2` is one tick. The renderer interpolates instances, poses and
  the camera from the previous tick to this one over the tick's length, so a game ticking
  at 20–35 Hz still draws smoothly at 60 Hz or more. `snap: true` places something
  without interpolating (teleports, new levels).
* **Frame of reference** — +Y up, the camera looking down its −Z, metres by convention.
  Converters for games in other units take a `:scale`.

## Where the frames go

| Use | How |
|---|---|
| A window | `CauldronGPU.open(title: ..., width: ..., height: ...)` |
| Pictures read back | `CauldronGPU.open(window: false, width: w, height: h)` then `CauldronGPU.capture/3` for RGBA bytes (`Cauldron3D.Scene.PNG.encode/1` saves one) or, with `shared_memory: name`, into a POSIX shared-memory object a terminal can read |
| Every frame, as drawn | `CauldronGPU.stream/2` sends each frame to a process (pixels, or a shared-memory name) until `stop_stream/1`; the receiver calls `frame_shown/1` for each, and at most `:ahead` frames wait at once. `CauldronGPU.Host` has the same calls |
| A terminal | A Cauldron game whose scene has a `:gpu`, run by `cauldron_2d_drafter`'s client: see `cauldron_examples/3d/courtyard` (`mix courtyard`), or a `cauldron_2d` game's `gpu` picture option below |
| Its own OS process | `CauldronGPU.Host` takes the same calls. A renderer crash leaves the VM running. `CauldronGPU.Host.restart/1` brings the renderer back with the scene it had |
| Browsers | `Cauldron3D.Net.Scene` in the `cauldron_3d_net` package |
| Livebook | `Cauldron3D.Kino` in the `cauldron_3d_kino` package |

Code that uploads should take any of these through the `Cauldron3D.Scene.Target` protocol
(`submit/2`, `mesh/2`, `texture/2`, `material/2`, `release/2`).

## Looks

* **Materials** (`Cauldron3D.Scene.Material`) are glTF-style metallic-roughness with base,
  emissive, normal and occlusion textures and baked lightmaps (with light styles), and
  game-style switches: `unlit`, `alpha_cutoff`, `alpha_mode` (`:blend`, `:add`,
  `:multiply`), `double_sided`, `sky`, `warp` (rippling liquids), `uv_scroll`,
  `uv_from: :reflection` and `smear` (the picture behind, shifted, for shimmering things).
* **Instances** (`Cauldron3D.Scene.Instance`) can be drawn `in_front` of the world (held
  weapons), with fixed `shading` instead of scene lights, without `depth_test`, `swell`ing
  along their normals, or `standing` in a room (not hidden by their own floor and
  ceiling, as sprites in sector games are not).
* **Environment** (`Cauldron3D.Scene.Environment`) sets the sky, ambient light, fog, exposure,
  tone mapping and bloom. The sky is shaded, or a picture: two scrolling layers or a
  six-sided box. Palette games can set `light_space: :display`, where light multiplies
  the display colour as colormaps do. They can also set `gamma`, `contrast`,
  `brightness`, and a `light_table` for light that falls off with distance.
* **Camera** (`Cauldron3D.Scene.Camera`) sets the field of view, near and far. Set `viewport`
  for a view that does not fill the frame, such as one above a status bar. Set `aspect`
  for non-square pixels and `resolution` for blocky low-detail views.
* **Effects** — `{:effects, [...]}` asks for `:ray_traced_shadows`,
  `:ray_traced_reflections`, `:ray_traced_ambient_occlusion`,
  `:ray_traced_global_illumination`, `:upscaling` and `:frame_generation`. A renderer
  that cannot do one leaves it out, so asking is always safe; `gpu.info` says what the
  device has.
* **On top** — `{:overlay, texture}` lays a picture over the finished frame (a HUD,
  menus; `{:overlay, texture, :premultiplied}` for additive pixels) and
  `{:screen_tint, {r, g, b, a}}` washes it (damage, pickups).

## Game formats

With `cauldron_3d` and `cauldron_3d_formats` (and `cauldron_2d` for sector maps) in your
deps, these converters upload a whole asset and give the changes that place it:

* `Cauldron3D.Scene.Bsp` uploads Quake and Half-Life maps. It brings their brush models,
  lightmaps with light styles, sky (`sky_layers/3`) and liquids.
* `Cauldron3D.Scene.AliasModel` uploads Quake `.mdl` models and animates them by blending
  keyframes.
* `Cauldron3D.Scene.StudioModel` uploads Half-Life studio models and skins them by bones.
* `Cauldron3D.Scene.Sectors` uploads Doom-style sector maps. `Cauldron3D.Scene.Sectors.Live`
  rebuilds sectors as doors and lifts move.
* `Cauldron3D.Scene.Placement` stands a model at a map point and angle.
* `Cauldron3D.Scene.Billboards` draws camera-facing pictures, such as sprites and particles,
  as one mesh.

## 2D layers

A tick can carry `{:layers, [layer]}`: 2D layers drawn every frame, in order, until the
next `:layers` change. A `Cauldron3D.Scene.SpriteLayer` draws `Cauldron3D.Scene.Sprite`s, each a
rectangle of a texture placed, scaled, turned, tinted and blended (`:over`, `:add` or
`:subtract`). A `Cauldron3D.Scene.ColumnLayer` redraws a texture column by column through a
table of positions, stretches and shades, for warps such as a curved view.

A layer draws into the frame or into a canvas. A canvas (`CauldronGPU.canvas/2`, a
`Cauldron3D.Scene.Canvas`) is a texture on the card, so a later layer can draw it as a sprite,
warp it, or a material can use it.

```elixir
alias Cauldron3D.Scene.{Canvas, Sprite, SpriteLayer, Texture}

{:ok, gpu} = CauldronGPU.open(title: "Sprites", width: 960, height: 600)
ship = CauldronGPU.texture(gpu, %Texture{width: 16, height: 16, pixels: pixels,
  format: :linear, filter: :nearest, wrap: :clamp, mipmaps: false})
screen = CauldronGPU.canvas(gpu, %Canvas{width: 320, height: 200})

CauldronGPU.submit(gpu, [
  {:layers,
   [
     %SpriteLayer{target: screen, clear: {0.0, 0.0, 0.1, 1.0},
       sprites: [%Sprite{texture: ship, position: {160, 100}, origin: {8, 8}, angle: 30}]},
     %SpriteLayer{clear: {0.0, 0.0, 0.0, 1.0}, view: {0, 0, 320, 200},
       sprites: [%Sprite{texture: screen, position: {0, 0}}]}
   ]}
])
```

Colours in layers are display values, blended as stored, the way `Cauldron2D.Blend` blends
bytes; upload 2D pictures with `format: :linear` so they reach the card unchanged. A pixel
is drawn when its centre lies inside the sprite, and takes the texel found by mapping that
centre back into the picture, so a sprite lands on the same pixels as
`Cauldron2D.DrawList` draws it. The frame's layers go over the 3D scene. A renderer that
has never been sent a camera draws its layers alone and skips the 3D passes.

## Drawing a cauldron_2d game on the graphics card

A `Cauldron.Client.Game` whose scene has a `:picture` (its own software renderer) can add
a `:gpu` function describing the same picture for the card. The client in
`cauldron_2d_drafter` then draws it on the graphics card by default, and falls back to the
software picture when the card is not there.

```elixir
def scene(view, look) do
  %{
    focus: {0.0, 0.0},
    bounds: :unbounded,
    cell: fn _ -> nil end,
    movers: [],
    picture: fn size, aspect -> MyGame.Render.picture(view, size, aspect) end,
    gpu: fn target, cache, size, aspect -> MyGame.Gpu.draw(view, target, cache, size, aspect) end
  }
end
```

`MyGame.Gpu.draw/5` answers `{changes, cache}`:

* `target` is a `Cauldron3D.Scene.Target`; upload through it.
* `cache` is what you answered last tick (`nil` the first time). Keep your handles in it
  (the level's meshes and materials, models seen so far, the overlay texture), keyed by
  level so a new level releases the old one's handles with `Cauldron3D.Scene.Target.release/2`.
* `size` is the picture's size in pixels and `aspect` how wide a pixel shows against its
  height; set the camera's `aspect` from it.
* `changes` is the tick: instances, camera, lights, light styles, and the game's 2D layer
  (status bar, messages, menus) as `{:overlay, texture}`, re-put under the same texture id
  each time it changes. A 2D game sends `{:layers, layers}` instead;
  `Cauldron2D.Drafter.Client.Sprites` turns `Cauldron2D.DrawList` items into sprites and
  uploads each picture once.

By default the card draws it offscreen and the client shows it in the terminal pane.
Each player can change that in the client's settings screen (the Drawing row: automatic,
software only, the card in the terminal, the card in a window of its own), and a run can
override it with the picture options `software`, `gpu` or `window`
(`Cauldron2D.Drafter.Client.Picture`), given as the `:picture` prop or `CAULDRON_PICTURE`.
In a window, keys pressed in the window drive the game. With no `:gpu` in the scene, no
renderer in the build, or a renderer that fails to open, the game's own picture is drawn
and the player sees a short note saying why. The renderer runs as a `CauldronGPU.Host`, so
a renderer crash does not take the game down.

`elixir_quake`, `elixir_doom` and `elixir_half_life` are complete examples of this in 3D,
and `nidhox` (`Nidhox.Gpu`) in 2D.

## Examples

The examples are their own project, `cauldron_examples/3d/gpu_showcase` in the Cauldron
repository. Run from there:

* `mix showcase` shows a courtyard with spheres, cubes and lamps. Fly
  with W A S D and the mouse. `EFFECTS=rt,gi,upscale` turns on ray tracing and upscaling.
* `mix spheres` is a load test with 2000 metal and plastic spheres
  (`COUNT=n`). Press `=` and `-` to add or take away 500. Once a second it prints the
  frames drawn and the graphics card's and renderer's time a frame. Frames are paced to
  the display, so frames a second stop at its refresh rate; the frame times show the
  room left.

`MIX_ENV=prod mix release` there builds the showcase as a program of its own, with the
runtime inside: `bin/gpu_showcase start` opens it (`SHOWCASE_ARGS` takes `mix showcase`'s
arguments), and a `.tar.gz` of it is written beside the release to hand to someone else.

The showcase builds its scene with `GpuShowcase.Courtyard`. The same courtyard in a
terminal, walked through with the keys and the mouse, is the Cauldron game in
`cauldron_examples/3d/courtyard` (`mix courtyard` there).

## Tests and status

`STATE.md` records what has been built, how it was checked, and what is open (DLSS and FSR,
Vulkan ray tracing on real hardware, first runs on Linux and Windows).

## License

[AGPL-3.0-only](https://github.com/jaman/cauldron/blob/main/LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](https://github.com/jaman/cauldron/blob/main/COMMERCIAL.md).
