# Changelog

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

### Breaking changes

* `Cauldron2D.Wx.Client` calls the game's `worlds/1` (was `arenas/1`); the `:link`
  function and the `:props` it is given work on those world entries.
* `Cauldron2D.Wx.Client` reads an outcome's `:next` as `:next_world` or `:same_world`
  (was `:next_arena` or `:same_arena`).
* Settings opened from a world remember it as `from: :play` (was `:arena`), and the
  client's state holds the world list as `:worlds` (was `:arenas`).

### Changed

* The lobby is titled "Worlds" and lists worlds.

## 0.1.0

* `Cauldron2D.Wx.View`, the socket and local links, `Wire`, `Input`, `Painter`,
  `Sheet`, `Sound`, `Const`: a `cauldron_2d` world in a wx window over the web wire or
  a process. `Cauldron2D.Wx.Text`: a canvas that draws a game's own screens as text
  items and hands the keys back.
* `Wire`, `Link.Socket`, `Link.Local` and `Sound` moved to `cauldron_2d_net` as
  `Cauldron2D.Net.*`; the view takes the same links under their new names.
* `Cauldron2D.Wx.View.pointer/2` and the `:pointer` option: whether the pointer aims.
* `Cauldron2D.Wx.View` `:on_stats`, `:show_stats` and `show_stats/2`: the frames received
  and the draws made each second, told to the game or drawn in the canvas corner.
* `Cauldron2D.Net.Link.Socket` delivers the server's `"audio"` format and takes an
  `:audio` option to ask for one; `Sound.format/3` reopens the speaker at it, and the
  view does so on its own.
* `Cauldron2D.Wx.View` `zoom: true` and `zoom/2`: `+`/`-`/`0` and the wheel change the
  tile size from 2 pixels (or the whole map in view) to 64; a map that fits in 4096
  pixels a side is drawn from one bitmap of it (`Painter.layer_blits/2`,
  `layer_offsets/4`, `mover_blits/4`). `Sheet.load/3` takes a fractional scale;
  `Sheet.unload/1`.
