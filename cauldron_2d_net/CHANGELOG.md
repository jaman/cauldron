# Changelog

## [0.4.0]

### Added

- `voice.js` (`window.CauldronVoice`), served by `Cauldron2D.Net.Pages` at `voice.js`: the browser side of `Cauldron.Net.Voice`, with calls, positional sound, and Opus over the channel when no direct route connects. While voice is on, the world page starts it on the game's socket as `window.cauldronVoice`; the served socket routes `"voice"`, and `Cauldron.mount` answers `socket()`.
- `Cauldron2D.Net.Pages` and `Cauldron2D.Net.Serve` take a `:drawer`; the world page loads that drawer's browser scripts and join params (`c:Cauldron.Net.Drawer.browser/0`), and `cauldron.js` hands the canvas to a script that sets `window.CauldronDrawer`. `Serve` with `drawer: Cauldron3D.Net.Drawer` serves a 3D game.

### Changed

- A served world is drawn by the client from scene data by default (`Cauldron2D.Net.Drawing`'s default is `:client`); pictures drawn by the server are what a game asks for with `drawing: :server`, or what a scene the client cannot draw from data gets.
- Every frame the world sends a session is drawn: `Cauldron2D.Net.Drawn.tick/2`, `rate/2` and `frame_ms/0` are removed, the world's own pacing (`Cauldron.Player.frames/3`) being the only limit.
- A long hud row wraps in the world page's side panel.
- Depends on `cauldron_core` 0.4 and `cauldron_2d` 0.4: the engine modules that moved from `cauldron_2d` are named `Cauldron.*`, and test and example games write `use Cauldron2D.Client.Game`.
- The socket, channel, sessions, sound policy, API, remote calls, links and load test
  move to the new `cauldron_net` package as `Cauldron.Net.*`, which this package
  depends on. What stays here is 2D: `Cauldron2D.Net.Drawer`, the `Cauldron.Net.Drawer`
  that sends a 2D scene as a picture or as scene data, with `Drawing`, `Drawn`, `Atlas`,
  `Scene` and `Picture`; the pages; and `Serve`.
- `use Cauldron.Net.Channel` takes `drawer:` (for a 2D game `Cauldron2D.Net.Drawer`, or
  `{Cauldron2D.Net.Drawer, opts}` with `:sheet_url` and `:drawing`) instead of
  `drawing:`; `use Cauldron.Net.Socket` no longer takes `:sheet_url`.
- `Session.join/5`, `FrontSession.open/5`, `Link.Local` and `Link.World` take
  `:drawer`; `Link.Socket` takes it to read the sheet, pictures and scenes, its `:atlas`
  going to the drawer. `Link.Local` joins with `local: true` in place of `drawing:
  :server, picture: :raster`.
- `Session.atlas_changed/1` is `Session.changed/2`, given the message.
- `Link.World.scene/1` is `Cauldron2D.Net.RemoteScene.scene/1`; `Wire.sheet/1` and
  `Wire.drawing/1` are `Cauldron2D.Net.Wire`'s.
- The application no longer starts processes of its own; `cauldron_net` starts them.

### Added

- `Session.rest/1`, `Session.wake/1`, `Link.Local.rest/1` and `Link.Local.wake/1`, passing on `Cauldron.Client.Stage.rest/1` and `wake/1` for a client sent to the background.
- `Session.without_gpu/1` and `Link.Local.without_gpu/1`: a client joined with `:gpu` whose graphics card would not open gets every scene as a picture from then on.

### Breaking changes

- Licensed under AGPL-3.0-only from this release; earlier releases were MIT. A game or
  service that uses it and does not publish its source needs a commercial license: see
  `COMMERCIAL.md`. `linocut` and `quake_c` stay MIT.
- The browser no longer draws a static map and movers from a sprite sheet. The server
  draws each frame with `Cauldron2D.Draw` and sends it as a PNG, or sends the scene as
  data for the browser to draw (`Cauldron2D.Net.Drawing`). The `map` and `frame` events
  are replaced by `drawing`, `status`, `picture`, `scene`, `overlay`, `tinted` and
  `tinted_cell`; the `sheet` event carries the `Cauldron2D.Net.Atlas` index.
- `Cauldron2D.Net.Sheet` is removed. Use `Cauldron2D.Net.Atlas` (`cached/1`, `index/2`).
- `Cauldron.Net.Frame.map/2` and `frame/4` are replaced by `Frame.status/3`;
  `Cauldron.Net.Wire.map/1` and `frame/1` by `Wire.status/1`, with `Wire.drawing/1`
  and `Wire.go/1` added.
- `Cauldron.Net.Keys.browser_keymap/1`, `browser_padmap/1` and `code/1` are removed.
  The browser sends raw keys and controller lines, and the server reads them with the
  game's keymap and padmap. `Keys` has `input_key/1`, `input_mods/1` and `browser_key/1`.
- The `input` channel event and `Cauldron.Net.Session.input/4` are removed. The browser
  sends `key` (down and up), `mouse`, `padline`, `hold`, `aim`, `pane`, `pan`,
  `recentre` and `configure`; `Session` has `key/4`, `mouse/2`, `pad_event/2`, `hold/4`,
  `aim/2`, `pane/2`, `pan/2`, `recentre/1` and `configure/2`.
- `Cauldron.Net.Link.Local.input/2` and `Cauldron.Net.Link.Socket.input/2` are
  removed. Use `key/4`, `mouse/2`, `pad_event/2`, `hold/4`, `pane/2`, `pan/2`,
  `configure/2` and `say/2`, and `Link.Socket.aim/2`. A link draws nothing until its
  owner gives the pane with `pane/2`.
- `Cauldron.Net.Link.World` views are `%{remote: remote, world: name}` (were
  `%{wire, map, sheet}`). Draw them with `Link.World.scene/1`, `hud/1` and `outcome/1`;
  `scene/2` and `labels/1` are removed. Pass `:atlas` for a server that leaves the
  drawing to its clients.
- `cauldron.js`'s mount options `keymap`, `padmap`, `steering`, `pause` and `zoom` are
  removed, and with them the handle's `zoom` and `zoomBy`. The server holds the keymap,
  the padmap and the zoom. The handle has `zoomIn()`, `zoomOut()`, `panBy(fx, fy)` (in
  fractions of the pane), `recentre()` and `say(text)`.

### Added

- `Cauldron2D.Net.Drawing`: who draws a served world, `:server` (the default),
  `:client`, `:split` or `[world: part, screen: part]`, from the `:drawing` option, the
  `CAULDRON_DRAWING` environment variable or `config :cauldron_2d_net, drawing: ...`.
- `Cauldron2D.Net.Picture` (a server-drawn frame as a truecolour PNG),
  `Cauldron2D.Net.Drawn` (a scene as the pushes for one client), `Cauldron2D.Net.Scene`
  and `Scene.Items` (a scene as data a client draws, each cell kind sent once) and
  `Cauldron2D.Net.Atlas` (the atlas packed for a client that draws, with tinted arts and
  cells).
- `priv/static/draw/*.js`: `Cauldron2D.Draw` in the browser (`window.CauldronDraw`),
  served by the pages at `draw/<file>`, and a Node check in `test/js` that holds it to
  the Elixir picture byte for byte.
- `Cauldron2D.Net.Serve`: serves a game to browsers and desktops on Bandit with no web
  code of the game's own; `--port` and `--drawing`.
- `Cauldron.Net.FrontSession`: the game's own title and summary (`fronts/1`) in the
  browser; the channel joins `front:title` and pushes `front` when a summary front
  takes over.
- The game's menu, look and client keys run on the server for a browser player
  (`Cauldron.Client.Stage`), with the `go`, `settings`, `clipboard` and `world`
  pushes; controllers and seats go through `Cauldron.Client.Party`.
- Chat: the lobby room on `chat:lobby`, the world's room on its channel (`say`,
  `chat_history`, `chat`, `talk`), chat panels on the lobby and world pages, and
  `Link.Local`/`Link.Socket` `say/2`. The rooms are `Cauldron.Chat`'s.
- The settings page offers the frame rate and whether the pointer aims beside the key
  preset; the world sends a player frames at the rate they chose.

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

### Breaking changes

* The HTTP API lists worlds at `GET /worlds` (was `/arenas`); `GET /stats` answers
  `worlds` (was `arenas`); the board narrows with `world=<name>` (was `arena=`).
* `arena_json/1` in `Cauldron2D.Net.Api` is now `world_json/1`.
* The pages serve `worlds.json` (was `arenas.json`) and a world at `/world/:id` (was
  `/arena/:id`). The page's element ids and classes are `world`, `worlds` and
  `world-page` (were `arena`, `arenas` and `arena-page`); a stylesheet or script of the
  game's that targets them must follow.
* `Cauldron2D.Net.Pages`, `Socket` and `Channel` call the game's `worlds/1` (was
  `arenas/1`) and cue music with `cue(view, :play)` and `cue(view, {:static, :play})`
  (was `:arena`).
* `Cauldron2D.Net.Audio` music policy `:world` (was `:arena`).
* `arenas/1` in `Cauldron2D.Net.Remote` is now `worlds/1`, `node_arenas/1` is now
  `node_worlds/1`, and the `arena()` type is `world()`. `stats/1` answers `worlds:`, and
  `leaders/4` takes `world:` (was `arena:`).
* `Cauldron2D.Net.Link.World` takes `:world` (was `:arena`), and the view it hands a
  player is `%{wire, map, sheet, world}` (was `arena`).
* `Cauldron2D.Net.Load` takes `:worlds` (was `:arenas`), and its reports carry
  `server.worlds` (was `server.arenas`). `Cauldron2D.Net.Load.Session` takes `:world`
  (was `:arena`).
* A `{module, function}` `:sheet_url` is called each time a sheet is sent — at the join
  and on every atlas change — rather than once at the connect.

### Added

* A session starts its audio with the game's `audio/0` settings (`:voices`,
  `:earshot`).
* Game controllers in the browser: the world page loads `gamepad.js` (served by
  `Cauldron2D.Net.Pages` at `/gamepad.js`) and mounts `cauldron.js` with the game's
  `padmap/1`, asked with `%{username: name}` (`Cauldron2D.Input.Pad.default_map/1` of its
  actions without one). Buttons hold in full; an axis past `pad: {deadzone}` (default
  0.3) holds at its magnitude as `strength`.
* `Cauldron2D.Net.Keys.browser_padmap/1`: a padmap as `cauldron.js` takes it, with
  `buttons`, `axes`, `aim` and `push`.
* A padmap's `aim: [{:stick, :left | :right}]` makes that stick aim eight tiles from the
  focus the way it points (`cauldron.js` `pad: {distance}`), following the focus while
  held and letting go when it centres. `aim: [{:stick, side, push: [action:, beyond:,
  least:, gain:]}]` also holds an action past `beyond` at a strength that grows with the
  push.
* `cauldron.js` `touch: {tilt: {range, deadzone, distance, smoothing, invert}}`: the
  device's tilt aims, `range` degrees from the pose it was first read in being full
  deflection, levelled again when the screen turns or the page comes back. A stick zone
  takes the aim from tilt only past its `push.beyond`, and holds its push action from
  the lightest touch while tilt aims.
* `cauldron.js` handle: `aim(point)`, `hold(action, down, strength)`, `focus()` and
  `input()`, for a page adding an input source of its own.

### Changed

* Depends on the `gamepad` package.
* `cauldron.js`: a controller holding a steering action drops the pointer's aim, as a
  steering key does.

### Fixed

* `Cauldron2D.Net.Link.World` takes `Cauldron2D.World.join/4`'s join, and a player
  joined with `frames: false` is sent no frames and plays no sound.
* `cauldron.js` tilt on iOS asks for motion permission from a tap only, never at mount,
  so tilt steering starts on the first tap.

## 0.1.0

* `Cauldron2D.Net.Game` behaviour (it became `Cauldron2D.Client.Game`), `Sheet`, `Frame`, `Session`, `Channel` and
  `priv/static/cauldron.js`: a `cauldron_2d` world on a canvas over a Phoenix channel, with
  the player's sound as binary PCM on the same socket.
* `Cauldron2D.Net.Wire`, `Link.Socket`, `Link.Local` and `Sound` — the wire's Elixir
  client side — moved here from `cauldron_2d_wx`; their messages are tagged
  `:cauldron_link` (were `:cauldron_wx`). Depends on `mint` and `mint_web_socket`.
* `cauldron.js`: `onStats` and `stats()`, the frames received and the draws made each
  second, for a page that shows a frame rate.
* `cauldron.js`: `touch: {zones}` — buttons and a thumbstick the page lays out, by
  pointer id; `fit: true` — the canvas sized to its box at the device pixel ratio;
  `aimEvery` — paced input messages for a moving aim; hud rows tagged by the game
  get `class="hud-<tag>"`; a hidden tab releases every key.
* `Cauldron2D.Net.Game.hud/1` rows may be `{tag, row}`; `Frame.frame/4` sends the tags
  beside the rows as `tags` when any row has one.
* The PCM format is the browser's choice: `cauldron.js` `audio: {rate, channels}` →
  join param → `Channel.audio/1` → `Session.join/5` `:audio`; the `"audio"` push tells
  the browser what comes; `use Cauldron2D.Net.Channel, audio:` sets the game's default.
  A stick zone's `push: {action, beyond, least, gain}` holds an action while the stick
  is pushed past `beyond`, with a `strength` that grows with the push; the input message
  may carry `strength` (action to 0.0–1.0), validated by `Session.input/4`.
* Input messages are not logged (`log_handle_in: false`).
* `cauldron.js` `zoom: {min, max, keys, wheel, pinch}`: `+`/`-`/`0`, the wheel and a
  pinch change the tile size, out as far as the whole map in view; `zoom(tile)` and
  `zoomBy(factor)` on the handle, `onZoom(tile)` in the options. The static map is
  drawn from one pre-rendered layer at the current size.
