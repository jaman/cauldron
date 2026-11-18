# The graphics card

`cauldron_gpu` draws a `cauldron_3d_scene` scene with Metal on macOS and Vulkan on Linux
and Windows. Elixir keeps the game world and sends what changed; a native render thread
draws at the display's rate from its own copy of the scene, interpolating between ticks.

The structs, the change stream and the `Cauldron3D.Scene.Target` protocol are in
`cauldron_3d_scene`. This package is the renderer, and code that only describes scenes
does not need it.

## What it needs at run time

The package always compiles; the native renderer is built when what it needs is on the
machine. At run time it needs a built renderer, one backend it can load, and a driver:

| Platform | Backend | The build needs |
| --- | --- | --- |
| macOS | Metal, and Vulkan when found | Apple's command-line tools, SDL3, `pkg-config`; for Vulkan, its loader and headers, and MoltenVK |
| Linux | Vulkan | a C++20 compiler, `make`, `pkg-config`, SDL3, Vulkan's headers, a Vulkan driver |
| Windows | Vulkan | MSVC's C++ Build Tools, SDL3's development files, Vulkan's headers, a Vulkan driver |

`mix cauldron_gpu.setup` looks for each thing in the platform's usual places, offers to
install what is missing — showing what it will run — builds the renderer, and opens the
graphics card to check it. Declining leaves software drawing, and running it again starts
over.

```sh
mix cauldron_gpu.setup
mix cauldron_gpu.setup --check
mix cauldron_gpu.setup --software
```

`--check` only reports, `--yes` accepts every automatic install, and `--software` builds
no renderer. The paths found are kept in `build.config` under
`:filename.basedir(:user_config, "cauldron_gpu")`, so later builds use them without
environment variables; downloads go to `:filename.basedir(:user_cache, "cauldron_gpu")`.
`CauldronGPU.Setup.read_config/0` answers the file and `CauldronGPU.Setup.config_path/0`
its path.

Environment variables set by hand take precedence: `SDL3_DIR`, `VULKAN_INCLUDE` (or
`VULKAN_SDK`), `PKG_CONFIG` and `PKG_CONFIG_PATH`. `CAULDRON_GPU_VULKAN=0` leaves Vulkan
out of a macOS build; Metal is used first on a Mac.

Shaders come compiled in `priv/shaders`, with separate sets for the iOS and tvOS builds.
`make shaders` rebuilds them from `shaders/`, which needs the Slang compiler (`make slang`)
and, for Metal, Xcode.

Check what a build has without opening a window:

```elixir
CauldronGPU.backends()
#=> [:metal]

CauldronGPU.Setup.card_status()
#=> {:ok, device, [:metal]}
```

`card_status/0` answers `{:error, text}` saying why when the renderer has not been built
or cannot open the card.

## Opening a device

`CauldronGPU.open/1` opens a window or an offscreen device.

| Option | Meaning |
| --- | --- |
| `:title` | the window's title, default `"cauldron_gpu"` |
| `:width`, `:height` | points for a window, pixels for an offscreen device; default 1280×720 |
| `:backend` | `:metal` or `:vulkan`, default the first of `CauldronGPU.backends/0` |
| `:events` | the process window events go to, default the caller |
| `:window` | `false` for no window; a frame is drawn for each submit and capture |
| `:surface` | a native surface to draw into instead of a window, as an integer |

```elixir
alias Cauldron3D.Scene.{Camera, Instance, Light, Material, Mesh, Transform}

{:ok, gpu} = CauldronGPU.open(title: "Hello", width: 1280, height: 720)

cube = CauldronGPU.mesh(gpu, Mesh.cube(1.0))
red = CauldronGPU.material(gpu, %Material{base_color: {0.8, 0.1, 0.1, 1.0}, roughness: 0.4})

CauldronGPU.submit(gpu, [
  {:instance, 1, %Instance{mesh: cube, materials: [red]}},
  {:light, 1, %Light{kind: :directional, direction: {-0.4, -1.0, -0.3}, shadows: true}},
  %Camera{position: {0.0, 1.0, 4.0}}
])
```

`gpu.info` says what the device has: `:backend`, `:device`, `:ray_tracing`,
`:mesh_shaders`, `:unified_memory`, `:upscaling` and `:frame_generation`.
`Cauldron3D.Scene.Target.capabilities/1` turns those into the three questions a game
asks — ray tracing, upscaling, frame generation.

Window events arrive at the `:events` process as `{:cauldron_gpu, window_id, event}`:
`{:key, :down | :up, key, repeat?}`, mouse motion, buttons and wheel, `{:resized, width,
height}`, `{:focus, boolean}`, `:close_requested`, and `{:error, message}`.

On macOS the window runs on the process's main thread, which the first `open/1` takes for
the rest of the VM's life; `wx` cannot open windows in the same VM.

`CauldronGPU.close/1` closes the window; later calls with the same `gpu` answer
`{:error, "closed"}`.

## How a scene becomes GPU work

A mesh, texture, material or scatter is uploaded once and answered with a
`Cauldron3D.Scene.Handle`. Uploading again under a handle's id replaces it, which is how a
per-tick mesh — particles, a HUD texture — is updated:

```elixir
CauldronGPU.submit(gpu, [{:mesh, cube.id, Mesh.cube(2.0)}])
```

Everything else is a list of changes, `Cauldron3D.Scene.Stream` lists them all: instances,
moves, poses, lights, the camera, the environment, light styles, the overlay picture, the
screen tint and effects. `CauldronGPU.submit/2` puts a `:tick` at the front of the list,
turns it into the stream's binary, and hands it to the renderer.

The renderer interpolates instances, poses and the camera from the previous tick to this
one over the tick's length, so a game ticking at 20–35 Hz still draws smoothly at the
display's rate. `snap: true` places something without interpolating, for teleports and new
levels.

`:effects` asks for `:ray_traced_shadows`, `:ray_traced_reflections`,
`:ray_traced_ambient_occlusion`, `:ray_traced_global_illumination`, `:upscaling` and
`:frame_generation`. A renderer that cannot do one leaves it out, so asking is safe.

`CauldronGPU.stats/1` says how drawing is going:

```elixir
%{frames: frames, gpu_ms: gpu_ms, cpu_ms: cpu_ms} = CauldronGPU.stats(gpu)
```

`CauldronGPU.frames/1` counts the frames drawn into the window.

## Sending textures

`CauldronGPU.texture/2` uploads a `Cauldron3D.Scene.Texture`. A texture holding a PNG or
JPEG file is decoded first, on a dirty scheduler, by `CauldronGPU.decode/1`;
`CauldronGPU.decode!/1` raises instead of answering an error. `CauldronGPU.decoded/1`
does the same to the textures in a list of changes.

`CauldronGPU.reduce_image/2` shrinks a picture so its longest side is at most `:max_side`
pixels (default 2048) and writes it again as JPEG at `:quality`, or PNG when a pixel is
see-through.

## Where the frames go

| You want | Call |
| --- | --- |
| A window | `CauldronGPU.open(title: ..., width: ..., height: ...)` |
| The next frame as bytes | `CauldronGPU.capture/3` |
| Every frame, as drawn | `CauldronGPU.stream/2`, until `CauldronGPU.stop_stream/1` |
| The renderer in its own OS process | `CauldronGPU.Host` |
| A browser | `Cauldron3D.Net.Scene` in `cauldron_3d_net` |
| A Livebook cell | `Cauldron3D.Kino` in `cauldron_3d_kino` |

```elixir
{:ok, gpu} = CauldronGPU.open(window: false, width: 640, height: 360)

CauldronGPU.submit(gpu, [%Camera{position: {0.0, 1.0, 4.0}}])
{:ok, frame} = CauldronGPU.capture(gpu)

File.write!("frame.png", Cauldron3D.Scene.PNG.encode(frame))
```

`capture/3` answers `{:ok, %{width: w, height: h, pixels: rgba}}`, tone-mapped and
sRGB-encoded, rows from the top. With `shared_memory: name` it writes the pixels into the
POSIX shared-memory object `name` instead — at most 31 bytes on macOS, starting with `/`
— and answers the name. That is not available on Windows;
`CauldronGPU.remove_shared_memory/1` removes an object that was never read.

`stream/2` sends the calling process every frame the renderer draws as
`{:cauldron_gpu, id, {:frame, width, height, pixels}}`. At most `:ahead` frames (default
2) wait for the receiver to call `CauldronGPU.frame_shown/1`, so a slow receiver gets
fewer frames instead of a growing mailbox. An offscreen device draws at `:fps` (default
60) while streaming, whatever is submitted; a window draws at its display's rate.

```elixir
:ok = CauldronGPU.stream(gpu, shared_memory: ["/frame_0", "/frame_1"])

receive do
  {:cauldron_gpu, _id, {:frame, width, height, {:shared_memory, name}}} ->
    IO.puts("#{name} is #{width}x#{height}")
    CauldronGPU.frame_shown(gpu)
end
```

## In its own process

`CauldronGPU.Host` takes the same calls with the same arguments and answers the same
values, so a caller switches by module. The renderer runs in its own OS process; a crash
in it leaves the VM running, and the `:events` process receives
`{:cauldron_gpu, window_id, :renderer_exited}`. `CauldronGPU.Host.restart/1` starts a new
one and sends it the kept scene. `CauldronGPU.Host.os_pid/1` says which process it was.

Handles there are not freed by garbage collection: `CauldronGPU.Host.release/2` releases
one, and every handle a process made is released when that process exits. A change batch
of `:shared_memory_threshold` bytes or more (default 262144) reaches the renderer through
a POSIX shared-memory object rather than a pipe.

## The `:gpu` picture option in a terminal client

A client of `cauldron_2d_drafter` draws its picture in the terminal pane. A game whose
scene describes its own software picture can add a `:gpu` function describing the same
picture for the card:

```elixir
def scene(view, _look) do
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

`MyGame.Gpu.draw/5` answers `{changes, cache}`.

* `target` is a `Cauldron3D.Scene.Target`; upload through it.
* `cache` is what you answered last tick, `nil` the first time. Keep your handles in it,
  one or a map keyed by level, and release the old level's handles with
  `Cauldron3D.Scene.Target.release/2`.
* `size` is the picture's size in pixels and `aspect` how wide a pixel shows against its
  height; set the camera's `aspect` from it.
* `changes` is the tick: instances, the camera, lights, light styles, and a 2D layer or an
  overlay for the HUD.

```elixir
def draw(_view, target, cache, {_width, _height}, aspect) do
  cube = cache || Cauldron3D.Scene.Target.mesh(target, Cauldron3D.Scene.Mesh.cube(1.0))

  {[
     {:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube}},
     %Cauldron3D.Scene.Camera{position: {0.0, 1.0, 4.0}, aspect: aspect}
   ], cube}
end
```

The client draws on the card by default. When there is no card it falls back to the
game's own picture, or to `Cauldron3D.Scene.Software` when the scene has none. Each
player can change that in the settings screen, and a run can override it with the picture
options `gpu`, `window` or `software` (`Cauldron2D.Drafter.Client.Picture`), given as the
`:picture` mount prop, `CAULDRON_PICTURE`, or the game's `look/0`. In a window, keys
pressed there drive the game.

The stage starts the first time a scene with a `:gpu` arrives, so a game that never
describes one never starts a renderer. It runs the renderer as a `CauldronGPU.Host`,
offscreen for the pane or in a window of its own, so a renderer crash does not take the
game down.

## Without a card

Where the renderer was not built, `CauldronGPU.backends/0` answers `[]`. Where no card
opens, `CauldronGPU.open/1` answers `{:error, reason}`. `mix cauldron_gpu.setup --check`
says which piece is missing.

The terminal client then falls back:

* a scene with a `:gpu` and no `:picture` of the game's own is drawn on the CPU by
  `Cauldron3D.Scene.Software`, where the build has `cauldron_3d`;
* a game's own `:picture` is drawn as it is;
* the player sees a short note saying why when the card was asked for by name.

`Cauldron3D.Scene.Software` implements the same protocol, so the `:gpu` function does not
change:

```elixir
parent = self()

{:ok, software} =
  Cauldron3D.Scene.Software.open(
    width: 480,
    height: 270,
    present: fn rgba, width, height -> send(parent, {:frame, rgba, width, height}) end
  )
```

It draws more plainly: no shadows, reflections, ray-traced effects, lightmaps and light
styles, normal and occlusion maps, sky pictures, fog, 2D layers or canvas contents. Its
capabilities are none of the effects, so
`Cauldron3D.Scene.Target.capabilities/1` answers `false` for each.

A scene that uses nothing beyond meshes, materials, lights, the camera and an overlay
looks much the same on either renderer; one that leans on the environment, shadows or
ray tracing does not.

## Where to go next

| You want to | Read |
| --- | --- |
| Describe the scene this draws | [`cauldron_3d_scene`'s scenes](https://hexdocs.pm/cauldron_3d_scene/scenes.html) |
| Read Quake, glTF or VRM files into it | [`cauldron_3d_formats`' files](https://hexdocs.pm/cauldron_3d_formats/files.html) |
| Draw without a card at all | [`cauldron_3d`'s software 3D](https://hexdocs.pm/cauldron_3d/software-3d.html) |
| Put the game in a terminal or a browser | [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter), [`cauldron_3d_net`](https://hexdocs.pm/cauldron_3d_net) |
