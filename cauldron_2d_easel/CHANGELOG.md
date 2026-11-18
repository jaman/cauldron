# Changelog

## [Unreleased]

### Changed

- Depends on `cauldron_core` 0.4 and `cauldron_2d` 0.4: the engine modules that moved from `cauldron_2d` are named `Cauldron.*`, and test and example games write `use Cauldron2D.Client.Game`.

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

* `Cauldron2D.Easel.Sectors`, a sector map document: rooms drawn as polygons on a grid and
  joined where they share a wall, heights, pictures and light per room and per wall,
  undo and redo, JSON files, and `to_map/2` to a `Cauldron2D.Sectors.Map` with its BSP.
* `Cauldron2D.Easel.SectorArt`, a palette and wall, floor and ceiling textures for
  previewing a sector map with no game art.

