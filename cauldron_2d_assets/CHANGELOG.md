# Changelog

## [Unreleased]

### Added

- Edits of a chosen picture (`from:`) and animations from video (`video:`,
  `Cauldron2D.Assets.Frames`). An asset's `negative:` is kept out of its clip as well.
- A build finds the Studio jobs it asked for before, by their `assets-<name>-<digest>`
  label, and waits for or uses them instead of asking again.

### Fixed

- A job longer than fifteen minutes no longer stops the build with a timeout: jobs are
  waited for in rounds until they end.

## [0.1.0]

### Added

- `Cauldron2D.Assets.Manifest`, `Spec`, `Lock`, `Build`, `Sheet` and `Studio`: a game's
  art asked of NxDiffusion Studio, chosen from sheets of candidates, finished as pixel
  art with `Linocut.Pixelate`, and kept reproducible by a lock file.
- `mix cauldron.assets` and `mix cauldron.assets.pick`.
