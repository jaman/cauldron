# Changelog

## [0.3.0]

The first release.

### Added

- `Cauldron3D.Net.Scene`: a scene server that keeps a `CauldronGPU` scene and
  broadcasts each tick as `CauldronGPU.Stream` bytes over a Phoenix channel; a
  `CauldronGPU.Target`, so the `cauldron_gpu` converters upload to it.
- `Cauldron3D.Net.Socket`, `Cauldron3D.Net.Channel` and `Cauldron3D.Net.Page`, and
  `cauldron3d.js`, which draws the scene with three.js and sends keyboard, mouse,
  resize and focus events back.
- 2D layers and canvases in the browser, over the 3D scene or alone.
