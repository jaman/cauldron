# Changelog

## [0.4.0]

### Breaking changes

- Licensed under AGPL-3.0-only from this release; earlier releases were MIT. A game or
  service that uses it and does not publish its source needs a commercial license: see
  `COMMERCIAL.md`. `linocut` and `quake_c` stay MIT.

### Changed

- Depends on `cauldron_core` 0.4 and `cauldron_2d` 0.4: the engine modules that moved from `cauldron_2d` are named `Cauldron.*`, and test and example games write `use Cauldron2D.Client.Game`.

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

### Changed

- The README is rewritten in plain sentences.

## [0.2.0]

### Added

* `Cauldron2D.Easel.Drafter.SectorEditor` and `mix cauldron.sectors`: draw rooms on a plan
  from above, walk through them in a first-person view beside it, and set each room's
  heights, pictures and light. `Cauldron2D.Easel.Drafter.Plan` is the plan widget.

