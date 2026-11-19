# Changelog

## [0.4.0]

### Added

- First release. `Cauldron2D.Assets.Manifest`, `Spec`, `Lock`, `Build`, `Sheet` and
  `Studio`: a game's art asked of NxDiffusion Studio, chosen from sheets of candidates,
  finished as pixel art with `Linocut.Pixelate`, and kept reproducible by a lock file.
- `mix cauldron.assets` and `mix cauldron.assets.pick`.
- Edits of a chosen picture (`from:`) and animations from video (`video:`,
  `Cauldron2D.Assets.Frames`). An asset's `negative:` is kept out of its clip as well.
- A build finds the Studio jobs it asked for before, by their `assets-<name>-<digest>`
  label, and waits for or uses them instead of asking again.
- Licensed under AGPL-3.0-only, with a commercial license for a game or service that does
  not publish its source: see `COMMERCIAL.md`.

### Fixed

- A job longer than fifteen minutes no longer stops the build with a timeout: jobs are
  waited for in rounds until they end.
- `Cauldron2D.Assets.Lock.read/1` parses the lock file and accepts only literal maps,
  lists, tuples, atoms, strings and numbers, raising on anything else instead of
  evaluating the file.
