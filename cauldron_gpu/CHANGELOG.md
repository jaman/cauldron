# Changelog

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
