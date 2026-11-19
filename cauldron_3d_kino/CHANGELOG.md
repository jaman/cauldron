# Changelog

## [0.4.0]

- Depends on `cauldron_3d_scene` (`Cauldron3D.Scene.*`); a Livebook scene reports no effects in `Cauldron3D.Scene.Target.capabilities/1`.

The first release.

### Added

- Licensed under AGPL-3.0-only, with a commercial license for a game or service that does
  not publish its source: see `COMMERCIAL.md`.
- `Cauldron3D.Kino`: a Livebook cell drawing a `CauldronGPU` scene in the browser with
  three.js; a `CauldronGPU.Target`, with input as `CauldronGPU` window events through
  `events/1` and `subscribe/1`.
- `notebooks/scene.livemd`: a lit scene, a turning cube, a mouse-driven camera,
  and the courtyard example's downloaded alley and atrium.
