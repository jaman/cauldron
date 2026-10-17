# Changelog

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
