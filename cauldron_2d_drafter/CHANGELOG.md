# Changelog

## [Unreleased]

### Breaking changes

* The `:start` mount prop names a flow, not a first screen. `:lobby` now opens on the
  title, then the lobby; pass `{:lobby, title: false}` for the lobby first (what
  `start: :lobby` did before, and what an embedding game passes). `:title` is read as
  `:lobby`.
* A game embedding the client under its own `Drafter.App` must add `controller: true`
  and `mouse_hover: true` to its `use Drafter.App` line.
* The client binds keys of its own by default: `v` cycles the projection, `[`/`]` turn,
  `'`/`;` tilt or pitch, and the controller's `Start` and bumpers. A game using any of
  them for its own actions rebinds or drops them through `client_keys/0` and
  `client_pad/0`.
* `Cauldron2D.Drafter.Client.arenas/1` is now `worlds/1`, calling the game's
  `worlds/1`.
* `Cauldron2D.Drafter.Client.next_arena/1` is now `next_world/1`, reading `:next_world`
  and `:same_world` from the outcome.
* The screen a world is played on is `:play` (was `:arena`), and the geometry event is
  `:play_geometry` (was `:arena_geometry`). The client's state holds the joined world as
  `:joined` (was `:arena`) and the summary's as `:summary_world` (was `:summary_arena`).
  Chat inside a world arrives as `{:chat, {:world, id}, message}`.
* `Cauldron2D.Drafter.Client.Screens.arena/1` is now `play/1`, and `arena_at/3` is now
  `world_at/3`.

### Added

* Five projections on `Cauldron2D.Drafter.Surface` through `:projection` — `:top`,
  `:oblique`, `:iso`, `:mode7`, `:first_person` — with `:facing`, `:facings` (a number,
  or a map per projection), `:tilt`, `:heading`, `:pitch`, `:eye` and `:density` (a
  number, or a map per projection). `Surface.projections/0`.
* `Surface` `:mode` takes the block-character glyph sets `:half`, `:quad`, `:sextant`
  and `:octant` beside `:braille`; every projection draws in them, and the plain glyph
  mode draws the isometric and oblique views.
* `Surface` options `:volumes` and `:layers` (`Cauldron2D.Parallax` layers, top-down);
  movers may be `{art, {x, y}, heading}` and are posed by their heading.
* `Surface.world_at/3` and `cell_at/3` map between a pane cell and a world point in
  every projection and drawing mode; `picture/2`, `drawn_mode/1`, `fitted/1`,
  `fitting_zoom/2`, `image_active?/1`, and `zoom_levels/3` for a projection.
* The isometric and oblique panes are stored once and shown through a moving source
  rectangle on a terminal with kitty placements; what moves is sent as patches
  (`Cauldron2D.Drafter.Surface.Patch.plan/4`).
* `Cauldron2D.Drafter.Client` flows: `enter/3`, `to_lobby/1`, `to_title/1`, `to_guide/1`
  and `home/1` for a game's own `start/0` function.
* Controllers: `{:controller, event}` goes through the game's `padmap/1` into the input
  sent to the world. The right stick nudges the aim or looks around, the triggers tilt
  or pitch, the d-pad and `A` choose and join in the lobby. A stick bound to `:aim`
  aims eight tiles from the focus and follows the focus while held.
* View keys and look: `client_keys/0` gains `projection`, `turn_left`, `turn_right`,
  `tilt_up`, `tilt_down`, and the unbound `display`, `glyphs` and `mouse_look`; the
  game's `look/0` sets the view a world opens in and `scene/2` is called when defined.
  A note under the world names the projection, its facing, tilt or heading and pitch,
  and how it is drawn.
* A drag turns and pitches the first-person and mode 7 eye, and turns an isometric view
  of more than four facings; a click still reaches the game. `turns_with_pointer?/1`.
* `Cauldron2D.Drafter.Client.steered/2`: direction actions turned with the isometric or
  oblique facing; in first person and mode 7 the input carries the eye's `:heading`.
* `Cauldron2D.Drafter.Client.scene/1`, `look/1` and `eye_height/2`; a scene's `:eye`,
  a height in tiles or an art, sets how high the first-person camera sits.
* `Cauldron2D.Drafter.Client.Settings` display choices `:half`, `:quad`, `:sextant` and
  `:octant`; `frame_rate/3` takes whether the terminal places images.

### Changed

* `:auto` frame rate is 12 on inline images (iTerm2's own, sixel), 20 on kitty without
  placements, 30 otherwise (was 15 and 30).
* `Surface.protocol/1` takes a forced mode, then `Cauldron2D.Renderer.resolved/1`, then
  `Drafter.Widget.Chart.Pixel.terminal/0`. Whether a terminal places stored images is
  `FrenchCurve.Capability.placements?/1` of the session's environment, which is false
  for every iTerm2.
* The client is `mouse_hover: true`, so a pointer aim previews without a click.
* Zoom levels follow the projection; zooming the isometric view out draws its world
  smaller in the same picture.
