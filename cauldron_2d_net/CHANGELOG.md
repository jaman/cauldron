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
