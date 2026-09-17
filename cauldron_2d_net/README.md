# Cauldron2D.Net

A `cauldron_2d` world over the network: the pieces a game needs to serve its worlds to
browsers, desktops and terminals elsewhere — over a WebSocket or from node to node —
and to reach a server from a client.

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_net, "~> 0.1"},
    {:phoenix, "~> 1.8"}
  ]
end
```

The world is a process; a browser player is a Phoenix channel process that joins it
like any other and forwards what the world sends. Rendering happens in the browser from
a sprite sheet fetched once; the server sends positions, hud text and sound, never
pixels. `CAULDRON_WEB_DESIGN.md` at the repository root is the design.

| module | what it is |
|---|---|
| `Cauldron2D.Net.Pages` | the pages around the worlds — title, lobby, arena, settings, guide — as a plug a game forwards a path to, from its `Cauldron2D.Client.Game` |
| `Cauldron2D.Net.Socket` | `use`d by a game's socket module: the player's name and settings from a verify function, the channel on the topic |
| `Cauldron2D.Net.Keys` | a game's keymap as `KeyboardEvent.code` names |
| `Cauldron2D.Net.Sheet` | a `Cauldron2D.Atlas` as one PNG plus an index of every art's place on it |
| `Cauldron2D.Net.Frame` | the wire form of the static map and of one tick's frame |
| `Cauldron2D.Net.Session` | a player's life on a channel: join, frames, input, levels, leave |
| `Cauldron2D.Net.Channel` | `use`d by a game's channel module; pushes frames as JSON and PCM as binary |
| `Cauldron2D.Net.Audio` | the server's sound policy: music per session, per arena (`Audio.Shared`, one stage a world), at a rate the node's load sets (`Audio.Governor`), or off; effects per session or off |
| `Cauldron2D.Net.Load` | a load test over the wire: sessions ramped until the worlds or the frames degrade, every report kept as JSON lines |
| `priv/static/cauldron.js` | `Cauldron.mount(canvas, opts)`: the channel, the canvas renderer, keys, pointer, on-screen touch zones the page lays out, Web Audio |
| `Cauldron2D.Net.Wire` | the channel protocol and the frame, map and sheet shapes, for an Elixir client |
| `Cauldron2D.Net.Link.Socket` | an Elixir client's connection to a server over its WebSocket |
| `Cauldron2D.Net.Link.Local` | the same connection to a world that is a process, here or on a connected node |
| `Cauldron2D.Net.Sound` | the PCM a link delivers, played through this machine's speaker |

A game implements `Cauldron2D.Client.Game` once, for every front end, and brings its
own Phoenix endpoint and login; `Cauldron2D.Net.Pages` gives it the pages. The audio bridge is
`TuningFork.Sink.Process`; each player's `Cauldron2D.Audio` runs on the server and its
PCM rides the same socket as the frames.

## The wire

| event | payload |
|---|---|
| `sheet` | `{url, tile, columns, void, arts: {name: index}, frames: [[x, y]…], anim: {"index": {indices: [index…], fps}}}` |
| `map` | `{width, height, tile, wrap, rows: [[index…]…]}` once, 0 for nothing |
| `frame` | `{focus: [x, y], movers: [[index, x, y]…], labels: [[text, x, y, "#rrggbb", scale]…], hud: [[[text, "#rrggbb" or null]…]…], tags: [name or null…] when any row has one, over: {title, lines} or null}` |
| `audio` | `{rate, channels}` the PCM comes in, or `{off: true}` for none; a join param `audio` of `{rate, channels}` asks for a format, `false` for none |
| `pcm` (binary) | signed 16-bit little-endian PCM in the `audio` format |
| `input` (browser → server) | `{held: [action…], aim: [x, y] or null}` |
| `levels` (browser → server) | `{sfx, music}` |
| `music` (browser → server) | `{on: true or false}`, the music off or back at its level, the effects untouched |
| `pause` (browser → server) | `{}`, pauses or resumes a world of the player's own |

## The view in the browser

`Cauldron.mount(canvas, opts)` draws the world around the frame's focus: the static map
from cached chunks of about a thousand device pixels a side, only those in view drawn
and at most sixteen kept, so no canvas ever nears a browser's size limit whatever the
map, the zoom or the screen's pixel ratio; movers, labels and animated cells over it. With
`zoom: {min, max, keys, wheel, pinch}` the player zooms: `+`/`=` and `-`, the wheel, a
pinch, `0` back to `scale`; `game.zoom(tile)` and `game.zoomBy(factor)` from the page.
Watching — `spectate` among the join `params`, or `watching: true` — the view can be
moved as well: the arrows, a drag with the mouse or one finger pan it, the wheel and a
pinch zoom about the pointer or the fingers, `0` recentres; `game.panBy(dx, dy)` in
tiles and `game.recentre()` from the page. Flying, the view stays on the ship, and the
aim is where the mouse is on the screen: it is worked out again from the mouse's last
place after every draw, so a ship flying under a still mouse keeps aiming at the point
ahead of it rather than at the spot the mouse last passed over. `game.levels(sfx, music)`
sets the sound levels and `game.music(on)` switches the music off or back on at its level.

## License

MIT
