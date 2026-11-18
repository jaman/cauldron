# Changelog

## [Unreleased]

### Changed

- Depends on `cauldron_core` 0.4 and `cauldron_2d` 0.4: the engine modules that moved from `cauldron_2d` are named `Cauldron.*`, and test and example games write `use Cauldron2D.Client.Game`.
- Depends on `cauldron_net` for the links (`Cauldron.Net.Link.Socket`, `Link.Local`, `Sound`); `Cauldron2D.Wx.View.join/3` starts a link with `drawer: Cauldron2D.Net.Drawer` unless given another.

### Breaking changes

- `Cauldron2D.Wx.View` shows the picture the link sends, or a scene the link decodes,
  drawn by `Cauldron2D.Draw`, and sends raw input: keys down and up, the mouse with the
  pointer as fractions of the picture, and controller events. The session on the far
  side reads them with the game's keymaps and padmap. Removed with this:
  - the `:keymap`, `:steering`, `:pointer`, `:input_every` and `:zoom` options
    of `View.new/2`, and `View.keymap/2`, `View.pointer/2` and `View.zoom/2`. Give the
    player's preset and pointer setting to `View.configure/2`; the client's zoom keys
    and the wheel zoom on the server.
  - `Cauldron2D.Wx.Input`. Raw input is read by `Cauldron.Client.Controls` and
    `Cauldron.Client.Party` in `cauldron_2d`.
  - `Cauldron2D.Wx.Painter` and `Cauldron2D.Wx.Sheet`. The picture is
    `Cauldron2D.Draw`'s.
  - `Cauldron2D.Wx.Keys.wx_keymap/1`. Use `Cauldron2D.Wx.Keys.input_key/1` to name a wx
    key code as `Cauldron.Input` does.
- `View.new/2`'s `:on_key` is called only while no link is joined.
- `View.new/2`'s `:scale` is screen pixels a picture pixel, default `2`;
  `Cauldron2D.Wx.Client.run/1`'s `:scale` defaults to `1`.

### Added

- `View.new/2` options `:on_go`, `:on_settings`, `:on_pad`, `:on_world` and
  `:controllers`; `View.configure/2`, `View.show/2` and `View.pane/2`; `View.join/3`'s
  `:watching`.
- A link to a server that leaves the drawing to its clients: give the socket link
  `:atlas`, and the view draws the scenes it receives, with the server's overlay.
- `Cauldron2D.Wx.Client` runs the game's own title and summary (`fronts/1`), opens where
  the game's `start/0` says, runs the game's menu, look and client keys in the world
  (`Cauldron.Client.Stage`), plays with game controllers, and has a lobby chat and a
  world chat in a game with chat.
- The settings screen offers the frame rate (`frame_rates/1`) and the game's own options.

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
