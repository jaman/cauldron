# Changelog

## [0.4.0]

### Breaking changes

- Licensed under AGPL-3.0-only from this release; earlier releases were MIT. A game or
  service that uses it and does not publish its source needs a commercial license: see
  `COMMERCIAL.md`. `linocut` and `quake_c` stay MIT.

### Changed

- The static build for an app (`make static`) covers iOS, tvOS and macOS and their simulators, compiling the Metal backend against `APPLE_SDK` and `APPLE_TARGET`; where the SDK has no MetalFX (the simulators) the renderer reports no upscaling or frame generation.
- The scene modules are `Cauldron3D.Scene.*` from `cauldron_3d_scene` (was `CauldronGPU.*` from `cauldron_gpu_scene`); `CauldronGPU` and `CauldronGPU.Host` report `Cauldron3D.Scene.Target.capabilities/1` from their renderer's info.

### Added

- `PriorityLayer`, a 2D layer of sprite tiles that show only where a coverage canvas lets them (the sprite-against-scroll-layer priority of Capcom's CPS2 board): the tile's priority in bits 3 to 5 of its flags is compared with the priority recorded in the coverage canvas, and a tile that does not show draws the colour the target held. It adds a `tile_priority` shader and a `coverage` descriptor to the layer structure (`GpuLayer` is 104 bytes).
- `TileLayer` and `ShadowLayer` 2D layers (palette-indexed tiles with mirror and transpose flags, and shadows that map the colour underneath), the `:r8` texture format and `srgb` canvases.
- Morph targets: the deform pass applies an instance's morph weights (up to 64 targets a mesh) before skinning, for the picture, shadows and ray tracing. The deform shader's push constants grew by 16 bytes.
- `CauldronGPU.open(surface: handle)` draws into a surface the host app made instead of a
  window: on iOS a `CAMetalLayer` with Metal, on Android an `ANativeWindow` with Vulkan,
  as `CauldronNative.gpu_surface/0` gives them.
- An Android build: the `static` Makefile target with `CAULDRON_TARGET=android` (Vulkan,
  loaded from the system's `libvulkan.so`; needs Vulkan's C++ headers on the Mac). Shared
  memory captures report themselves unavailable there.
- An iOS build: the `static` Makefile target (no SDL, Metal only, iOS 18 and later) and
  `priv/shaders/ios`, the shaders compiled for iOS (`make shaders-ios`). Frame generation
  needs iOS 26 and reports itself unsupported before.

### Changed

- The examples moved to `cauldron_examples/3d/gpu_showcase` in the repository, as Mix tasks
  (`mix showcase`, `mix spheres`) with a release of the showcase. The Quake, Doom and
  Half-Life examples are gone: they needed the games' own data.
- The structs, `CauldronGPU.Stream`, `CauldronGPU.Target`, `CauldronGPU.Host.Record`,
  `CauldronGPU.PNG` and the converters moved to the new `cauldron_gpu_scene` package,
  keeping their names. This package depends on it, so code using them needs no change.
- `cauldron_2d`, `cauldron_3d` and `cauldron_3d_formats` are now optional dependencies of
  `cauldron_gpu_scene`; here they are needed only by the examples.
- `examples/terminal.exs` is gone: a terminal is reached through a Cauldron game run by
  `cauldron_2d_drafter`'s client, as `cauldron/examples/courtyard` shows.
- `capture/3` answers as soon as the graphics card has finished the frame, instead of
  three frames later.

### Fixed

- The GPU host reads what its native process sends with `binary_to_term/2` and `[:safe]`, so
  a message naming an atom the node does not know is refused instead of creating it.
- On Metal, buffers and textures created while a frame is recorded are usable by that
  frame. The first captures after an upload, or after a quiet spell, came back black.
- Drawing costs a fraction of what it did at large sizes: 3.6 ms a frame at 2880×1700
  where it was 61 ms. The shaders copied the whole per-frame data into each pixel's memory
  when they looked up the sun's shadow; they now read it in place. Pictures are unchanged.

### Added

- `CauldronGPU.stream/2`, `stop_stream/1` and `frame_shown/1`, and the same in
  `CauldronGPU.Host`: every frame the renderer draws, sent to a process, with at most
  `:ahead` frames waiting. Offscreen devices draw at `:fps` while streaming.
- PNG and JPEG textures (`CauldronGPU.Texture.encoded/2`) are decoded by the renderer;
  `decode/1`, `decode!/1` and `reduce_image/2` decode and shrink pictures, using the
  vendored stb_image libraries.

## [0.3.4]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.3]

### Fixed

- On Windows the renderer loads the `SDL3.dll` beside it. Windows does not search a
  library's own folder for what it needs, so loading failed with "The specified module
  could not be found"; SDL3 is now delay-loaded and loaded from that folder first.
- MSVC builds without warnings about `strncpy`, `getenv` and `_open`.

## [0.3.2]

### Fixed

- The host program (`cauldron_gpu_host`) builds on Windows: its pipes use the Windows C
  runtime in binary mode, and shared memory, which Windows builds do not use, reports
  itself unavailable there.
- An image's size in the Vulkan backend is set in a form every C++ compiler accepts.
- `mix cauldron_gpu.setup` stops after a failed build and says so, where it went on to
  check the card and crashed.

## [0.3.1]

### Added

- `mix cauldron_gpu.setup`: finds what building the renderer needs in each platform's
  usual places, offers to install what is missing (Homebrew on macOS; apt, dnf, pacman or
  zypper on Linux; winget and downloads on Windows), builds the renderer and opens the
  graphics card to check it. `--check`, `--yes` and `--software`.
- `CauldronGPU.Setup`: the build configuration the setup writes and every build reads,
  and `card_status/0`, whether the renderer loads and opens the graphics card.

### Changed

- The renderer builds with Vulkan's headers alone (`VULKAN_INCLUDE`); it loads the
  driver's Vulkan library when it runs, so Windows needs no Vulkan SDK.
- Without what the build needs, the package compiles with no renderer on Windows too,
  as it does on macOS and Linux, and games draw in software.

## [0.3.0]

The first release.

### Added

- 3D scenes drawn by the graphics card from a change stream sent from Elixir
  (`CauldronGPU.Stream`): meshes, textures, materials, instances, poses, lights, camera,
  environment, light styles, overlay and screen tint, moved smoothly between ticks.
- A Metal backend on macOS and a Vulkan backend for Linux, Windows and macOS (MoltenVK):
  deferred lighting, cascaded shadows, transparency, bloom and tone mapping, with
  ray-traced shadows, ambient occlusion, reflections and one-bounce global illumination,
  and MetalFX upscaling and frame generation, on Metal.
- 2D layers: `{:canvas, id, %CauldronGPU.Canvas{}}` and `{:layers, [layer]}` with
  `CauldronGPU.SpriteLayer` (`CauldronGPU.Sprite`s placed, scaled, turned, tinted and
  blended over, added or subtracted) and `CauldronGPU.ColumnLayer` (a texture redrawn
  through a per-column table). Sprites land on the same pixels as `Cauldron2D.DrawList`.
- Windows with keyboard and mouse events, offscreen rendering, frame capture (into
  shared memory too) and the terminal's size.
- `CauldronGPU.Host`: the renderer in its own OS process, restarted with its scene.
- `CauldronGPU.Target`: one protocol for the renderer, the host and browser scenes.
- Converters for Quake BSP maps and alias models, Half-Life studio models and Doom
  sectors, and camera-facing billboards.
