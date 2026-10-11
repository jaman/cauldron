# Changelog

## [0.2.0]

### Added

* `Linocut.squash/3`: a picture scaled to a share of its size on each axis and placed back
  in a canvas of the original size, `anchor: :centre | :bottom`, `lean: -1.0..1.0`.
* `Linocut.Derive` op `scale N`: every key repeated `N` times each way.
* `Linocut.Resample.to/3`: a picture redrawn at another size, `mode: :area` (default) or
  `:nearest`.
* `Linocut.Quantise`: `reduce/3`, `palette/3`, `to_palette/3`, `nearest/2` — a picture
  reduced to a median-cut palette.
* `Linocut.Seam.close/2`: a picture made to tile along `:x` and `:y`.
* `Linocut.Sheet`: `cut/2`, `cut_all/2`, `rows/2`, `runs/2` — a sprite sheet with a clear
  background cut into same-size frames standing on one floor.
* `Linocut.Frames`: `align/2` lines separately drawn frames up on one canvas, `to_pic/3`
  writes them as `.pic` text with a shared palette.
* `Linocut.Pose`: `walk/2`, `skeleton/3`, `joints/0` — a walk cycle's joints and their
  OpenPose skeleton picture.
* Mix tasks `linocut.import` (an image to a `.pic` at a size and palette),
  `linocut.sheet` (a sprite sheet to a `.pic` of frames), `linocut.join` (separate
  pictures to the frames of one `.pic`) and `linocut.pose` (OpenPose skeletons for a
  cycle).
