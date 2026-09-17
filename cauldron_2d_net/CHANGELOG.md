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
* Input messages are no longer logged (`log_handle_in: false`).
* `cauldron.js` `zoom: {min, max, keys, wheel, pinch}`: `+`/`-`/`0`, the wheel and a
  pinch change the tile size, out as far as the whole map in view; `zoom(tile)` and
  `zoomBy(factor)` on the handle, `onZoom(tile)` in the options. The static map is
  drawn from one pre-rendered layer at the current size.

## 0.1.0

* `Cauldron2D.Net.Game` behaviour, `Sheet`, `Frame`, `Session`, `Channel` and
  `priv/static/cauldron.js`: a `cauldron_2d` world on a canvas over a Phoenix channel, with
  the player's sound as binary PCM on the same socket.
