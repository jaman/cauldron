# Changelog

## [Unreleased]

- `cauldron3d.js` draws within a pixel budget and a frame cap set in the browser: by default at most 1920×1080 drawn pixels, scaled up to fill a larger window, and 60 frames a second. A browser keeps its own in `localStorage` (`cauldron3d.quality`); `?pixels=1280x720` (or `full`) and `?fps=30` (or `0` for every refresh) in the page address override it, and `window.cauldron3d.quality({pixels, fps})` changes it while running and answers the settings with the size being `drawn`. A headset session draws at the headset's own resolution.
- `Cauldron3D.Net.Drawer`: 3D games over `Cauldron.Net` sessions. Each client is sent its scene as a renderer's changes: stream bytes for a browser, drawn by `cauldron3d.js` in the game pages, and change terms for a desktop or phone client, drawn with its own renderer through `Cauldron3D.Net.RemoteScene` and `Cauldron3D.Net.Replay`. `Cauldron3D.Net.Outbox` is the target a scene's `:gpu` closure uploads to for one client, uploads from other processes included.
- `cauldron3d.js` exports `draw/1`, the scene without its own input handling; `Cauldron3D.Net.SceneState` gives its changes as terms as well as bytes.
- Depends on `cauldron_3d_scene` (`Cauldron3D.Scene.*`, was `cauldron_gpu_scene`); a browser scene reports no effects in `Cauldron3D.Scene.Target.capabilities/1`.

### Changed

- `cauldron3d.js` skins on the graphics card: a skinned instance is a `THREE.SkinnedMesh` bound
  to a `PosedSkeleton`, and each pose writes its bone matrices into the skeleton's texture. Posed
  instances share their mesh's geometry; only an instance blending between two keyframes meshes
  holds its own copy. Posed instances are not frustum-culled, as in `cauldron_gpu`.
- The showcase example moved to `cauldron_examples/3d/web_3d` in the repository (`mix
  showcase`); the Quake example is gone, as it needed the game's own data.
- A socket with no `:verify` connects without the check, so a module that uses
  `Cauldron3D.Net.Socket` without one compiles without a type warning.
- Depends on `cauldron_gpu_scene` instead of `cauldron_gpu`, so installing it no longer
  builds the native renderer.

### Added

- `cauldron3d.js` draws morph targets (stream operations 24 and 25) with three.js morph attributes and influences, for both the standard and the smear materials.
- `Cauldron3D.Net.SceneState`: the scene a browser is shown, as a value, with the bytes
  to send for each change. `Cauldron3D.Net.Scene` holds one; so does `Cauldron3D.Kino`.
- `cauldron3d.js` exports `mount(canvas, send)`, which draws a scene into a canvas
  without a Phoenix connection; `start` uses it.
- PNG and JPEG textures (stream op 23) are decoded in the browser with
  `createImageBitmap`.

## [0.3.4]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.3]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.2]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

## [0.3.1]

### Changed

- No changes in this package; released with the rest of the cauldron packages.

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
