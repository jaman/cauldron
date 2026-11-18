# Changelog

## [Unreleased]

- `Cauldron.Net.Drawer` no longer has `tick/2` or `rate/2`: a session asks `draw/2` for every frame, which the world already sends at the player's frame rate, every so many ticks.
- A channel gives its drawer the client's join params as `:params`, so a client can say how it wants scenes sent.
- `c:Cauldron.Net.Drawer.browser/0`, optional: the scripts, head HTML and join params a drawer's browser client needs.
- `Cauldron.Net.Voice`: voice calls between players, off until a game calls `open/1`. A call needs one player to ask and the other to agree. Sound goes directly between browsers, through a TURN server when one is set (Cloudflare, a shared secret or a fixed login, `Cauldron.Net.Voice.Ice`), and through the server's own channel when `relay: true` and no direct route connects. `Cauldron.Net.Socket` takes `voice: true` to route the `"voice"` topic to `Cauldron.Net.Voice.Channel`.

## 0.4.0

- First release. The parts of `cauldron_2d_net` that do not depend on how a game draws
  move here, as `Cauldron.Net.*`: the socket, channel, sessions, sound policy, API,
  remote calls, links and load test.
- `Cauldron.Net.Drawer`: what a client is sent to show each scene, and what a client
  makes of it. Sessions, front sessions, channels and links take a `:drawer` option.
- `Session.changed/2` and `FrontSession.changed/2` answer any message for the drawer;
  the channel and `Link.Local` route unknown messages to them.
- `Frame.status/4` takes the lookup for the colours a hud names.
- `Wire.field/2` reads a payload's field by atom or text key.
- `Sound` takes any `Cauldron.Audio.Sink` as its `:sink`.
- `Link.World` and `Link.World.Relay` keep what the drawer reads in the view's `remote`
  map; `Remote.Worlds` URL names carry the link world's options, `:drawer` among them.
