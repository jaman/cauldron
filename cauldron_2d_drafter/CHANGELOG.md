# Changelog

## Unreleased

### Changed

* A world the client starts for a game (an entry's `world: {module, opts}`) is started
  unlinked and linked once it runs; one that cannot start, such as a follower whose host
  cannot be reached, is a "could not join" note instead of a crash.

### Removed

* The client no longer passes frames through a game's `received/3`.

## [0.2.5]

### Added

* The client passes each frame's
 view and events through the game's `received/3`
  (`Cauldron2D.Client.Game`) and keeps what it returns for the next frame, from a
  world's first frame on.

## [0.2.2]

### Added

* `Cauldron2D.Drafter.Client.Picture`: how a game's picture reaches a terminal that
  keeps images (`native`, `native:N`, `size:WxH`, `png`, `swap`, `none`), read from the
  client's `:picture` mount prop, the application env `config :cauldron_2d_drafter,
  picture:`, the `CAULDRON_PICTURE` environment variable or the game's look, with
  `parse/1` for a mix task's `--picture`. Default `native:2,swap`.
* A look's `:native` and `:picture` keys: a picture's own size, and the game's default
  picture options.
* The client's `:mute` mount prop, `config :cauldron_2d_drafter, mute: true` and
  `CAULDRON_MUTE=1`: no sound, whatever sink the game or session would have had.

### Breaking changes

* A scene's `:native_scale`, `:picture_format` and `:swap` keys are no longer read; the
  client's picture options decide them. A scene's `:native` still declares the
  picture's own size.

## [0.2.0]

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
* `arenas/1` in `Cauldron2D.Drafter.Client` is now `worlds/1`, calling the game's
  `worlds/1`.
* `next_arena/1` in `Cauldron2D.Drafter.Client` is now `next_world/1`, reading `:next_world`
  and `:same_world` from the outcome.
* The screen a world is played on is `:play` (was `:arena`), and the geometry event is
  `:play_geometry` (was `:arena_geometry`). The client's state holds the joined world as
  `:joined` (was `:arena`) and the summary's as `:summary_world` (was `:summary_arena`).
  Chat inside a world arrives as `{:chat, {:world, id}, message}`.
* `arena/1` in `Cauldron2D.Drafter.Client.Screens` is now `play/1`, and `arena_at/3` is now
  `world_at/3`.

### Added

* Three options for a surface's `:picture` on a kitty terminal, each independent and
  off by default: `:native` `{width, height}` asks the picture at its own size times a
  whole number (`:native_scale`, `:fit` or a number) for the terminal to scale to the
  pane; `picture_format: :png` sends it as a PNG; `swap: true` replaces it without a
  blank pane between frames. A game's scene gives them by the same names.
* `Cauldron2D.Drafter.Server.start/1` takes `port: 0` for any free port, and returns the
  port it serves on as `:port`.
* A world can ask the client to open the game's menu with an argument (`{:menu, arg}`),
  which a game answers with `open_menu/2`; one without it gets `open_menu/1`.
* Game controllers are tracked by name (`Cauldron2D.Drafter.Client.Controllers`): each
  plays a player of the client — the player itself, then its seats — by the settings'
  `pads` (a controller's name to a player number or `:none`), else the lowest free one
  in the order they connected; a controller with no player is ignored during play. A
  disconnect frees its player. The settings' `controllers` list the connected ones for
  the game's menus, and any controller works the game's menu while it is open.
* A game's `ask/1` can ask `{:enter, props}`: the client leaves its world, merges
  `props` into its mount props and joins the first world `worlds/1` then lists. When
  that world goes down, the client takes its earlier props back and joins the first of
  their worlds again.
* `local_seats/1` is given the client's props with `:settings`, and the seats take new
  keymaps when the game's menu changes the settings.
* The client acts on the game's `ask/1`: `:menu` opens the game's menu as the `menu`
  key does, `:quit` ends the client.
* A local seat joins with the prop `:seat_of`, the player's own username.
* Local seats: a game's `local_seats/1` keymaps each play a further player in the
  same world from the same terminal, joined as `"<username> 2"` and on without frames;
  keys reach every seat and count where they are mapped, and controllers go to the
  seats, the player's own first, in the order they first report
  (`Cauldron2D.Drafter.Client.Seats`).
* The client starts its audio with the game's `audio/0` settings (`:voices`,
  `:earshot`).
* The terminal client opens a game's own menu on its `menu` key (unbound until the game binds it): the player's held actions are let go, a world of their own is paused, and keys, mouse buttons, the wheel and the controller's d-pad, `A`, `B` and `Start` go to the game's `menu_event/3`; settings it changes are saved and take effect at once, and the scene is drawn again ten times a second for the menu's animations (`:menu_frame` on the look). Settings keep the game's own `:options`, which reach `scene/2` on the look and the world with every input, with the menu's requests.
* A game that binds the wheel gets it during play instead of the zoom, and a right stick
  the game's padmap binds holds the game's actions instead of nudging the aim. A notch
  of the wheel can be bound in the settings.
* Saved settings naming a preset the game no longer has start from the game's first
  preset, and the saved bindings go with the old preset.
* `Cauldron2D.Drafter.Surface` takes `:picture` — `fn {width, height}, aspect -> raster
  end` — and draws the game's own picture through the same pixel protocols and block
  glyphs as the atlas projections. The client passes a scene's `:picture` through.
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

* `gamepad` is a dependency, so the client's game controllers work in every game without
  the game listing it; a game that listed it only for the client can drop it.
* The client asks its world for frames at the rate it draws (20 a second over ssh, 30
  locally, or the frame rate chosen in settings) instead of every tick, so the world
  builds and sends no views that would not be drawn.
* `Cauldron2D.Drafter.Server.stop/2` takes a notice shown to each player it
  disconnects, whose terminal is restored. It returns once the port is closed, and
  disconnects the players and stops the accounts afterwards from a process of its
  own, so it can be called from a world those players' games call as they leave.
* A session served over ssh draws at 20 frames a second when its frame rate is
  `:auto`; local sessions keep 30.
* `Cauldron2D.Drafter.Server` gives each connection a 64 KiB send buffer (`:send_buffer`),
  so a session drawing faster than its connection carries skips frames instead of
  falling seconds behind, and players 10 minutes to log in (`:login_timeout`), ssh's
  host key question included, where they had two.
* A client whose name is already playing in a world joins it as `"<name> (2)"`, up to
  `"<name> (9)"`, instead of taking the other's player.
* `Cauldron2D.Drafter.Surface.world_at/3` on a `:picture` surface gives the point of the
  picture under the pointer as fractions of its width and height, and games playing a
  picture receive it as their input's `aim`. A scene with a `:frame` (the shape its
  screen is shown at) gets the point of that frame as `Cauldron2D.Fit.letterbox/3` places
  it, and `nil` on the bars around it. With the terminal reporting the pointer in pixels
  (drafter's `pixel_mouse`), a picture game's pointer is that pixel, not its cell.
* `:auto` frame rate is 12 on inline images (iTerm2's own, sixel), 20 on kitty without
  placements, 30 otherwise (was 15 and 30).
* `Surface.protocol/1` takes a forced mode, then `Cauldron2D.Renderer.resolved/1`, then
  `Drafter.Widget.Chart.Pixel.terminal/0`. Whether a terminal places stored images is
  `FrenchCurve.Capability.placements?/1` of the session's environment, which is false
  for every iTerm2.
* The client is `mouse_hover: true`, so a pointer aim previews without a click.
* Zoom levels follow the projection; zooming the isometric view out draws its world
  smaller in the same picture.

### Fixed

* A session served over ssh plays its sound to its account's tunnel port
  (`TuningFork.Sink.Tcp` to `127.0.0.1:<pulse_port>`), or nowhere without one.
* A player whose world stops — it crashed, or was stopped — is taken to the lobby and
  told "<world> stopped".
