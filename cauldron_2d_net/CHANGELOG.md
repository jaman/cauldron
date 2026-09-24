# Changelog

## Unreleased

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
* `cauldron.js` `touch: {tilt: {range, deadzone, distance, smoothing}}`: the device's
  tilt aims — `range` degrees from the pose it was first read in (levelled again when
  the screen turns or the page comes back) is full deflection, in the screen's frame —
  while a stick zone yields the aim to the stick only past its `push.beyond`, holding
  the push action from the lightest touch. Motion access is asked for on the first
  gesture where the browser requires it.
* A `{module, function}` `:sheet_url` is called each time a sheet is sent — at the join
  and on every atlas change — not once at the connect, so a browser fetches the new
  pixels at a new address when the atlas grows (`Cauldron2D.Net.Socket`, `Session`).
* `cauldron.js`: a controller holding a steering action drops the pointer's aim, as a
  steering key does, so a still mouse no longer steers against the pad until it moves.
* The world page asks the game's `padmap/1` with `%{username: name}`.
* A padmap's `aim: [{:stick, :left | :right}]` makes that stick aim — `Cauldron2D.Input.Pad.aim/1`
  is its direction — and both clients turn it into an aim eight tiles from the focus
  the way it points, let go when it centres (`Keys.browser_padmap/1` sends it as
  `aim`; `cauldron.js` `pad: {distance}`, default 8, and the pad drops the pointer's
  aim while it aims). The aim follows the focus while the stick is held: the terminal
  client re-aims on every world frame, `cauldron.js` on every draw.
* `cauldron.js` tilt asks iOS for motion permission only from a tap, never at mount:
  a request made with no gesture could stay pending and every later tap was ignored,
  so a page whose settings had already been allowed never steered by tilt.
* The terminal client turns and pitches the first-person eye on a mouse drag, whether
  or not `mouse_look` is on; a click still reaches the game.
* `cauldron.js`: the handle exposes the input — `aim(point)`, `hold(action, down,
  strength)`, `focus()`, `input()` — so a page can add an input source of its own on top
  of, or instead of, the built-in keys, pointer, touch, tilt and pad; the built-in tilt
  takes `invert`.
* An aim stick may push an action past its ring: `aim: [{:stick, :left, push: [action:
  :thrust, beyond: 0.6, least: 0.3, gain: 1.4]}]` holds `:thrust` at a strength that
  grows with the push, the rule the touch stick's `push` follows; `Keys.browser_padmap/1`
  sends it as `push` and `cauldron.js`'s pad holds it the same way.

* Input messages are no longer logged (`log_handle_in: false`).
* `cauldron.js` `zoom: {min, max, keys, wheel, pinch}`: `+`/`-`/`0`, the wheel and a
  pinch change the tile size, out as far as the whole map in view; `zoom(tile)` and
  `zoomBy(factor)` on the handle, `onZoom(tile)` in the options. The static map is
  drawn from one pre-rendered layer at the current size.

## 0.1.0

* `Cauldron2D.Net.Game` behaviour, `Sheet`, `Frame`, `Session`, `Channel` and
  `priv/static/cauldron.js`: a `cauldron_2d` world on a canvas over a Phoenix channel, with
  the player's sound as binary PCM on the same socket.
