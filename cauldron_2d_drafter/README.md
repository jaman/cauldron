# Cauldron2D.Drafter

Puts a [`cauldron_2d`](https://hexdocs.pm/cauldron_2d) world on screen through [drafter](https://hexdocs.pm/drafter). Two
tiers, and a game picks the one it needs:

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_drafter, "~> 0.1"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

* **Facilities** — a widget and helpers any drafter application drops into its own render
  tree. They assume nothing about what kind of game is on screen.
  * `Cauldron2D.Drafter.Surface`, the `cauldron_surface` widget: a viewport onto a grid and
    its movers, drawn as pixels where the terminal has them and glyphs elsewhere
  * `Cauldron2D.Drafter.Sprites`: sends an atlas to the terminal once so movers are
    placements
  * `Cauldron2D.Drafter.Chat`: rooms of messages that fan out to sessions
* **A ready-made client** — `Cauldron2D.Drafter.Client`, a whole drafter application for
  the shape "title, lobby of worlds, settings, world". It is boilerplate for that shape and
  nothing else in the library depends on it; a game with a different shape writes its own
  `Drafter.App` on the facilities.

## The surface

```elixir
{:cauldron_surface,
 [
   id: :map,
   atlas: :my_game,
   focus: {x, y},
   bounds: {width, height},
   cell: &MyGame.cell/1,
   movers: [{:ball, {7.42, 3.15}}],
   labels: [{"alice", {7.0, 2.0}, {255, 255, 0}}],
   flex: 1
 ]}
```

An art with frames is drawn at the frame showing on the clock; a label is text in
`Linocut.Font` over the world, or characters over the glyphs in text mode.

Register it before the first render, loading it first:

```elixir
Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
```

Registration reads the module's `component_tag/0`, which is only there once the module is
loaded; registering an unloaded module registers nothing, and its tag then renders as an
empty pane. The same goes for `Drafter.run/2`'s `:widget_libraries` option.

## The ready-made client

`Cauldron2D.Drafter.Client` runs a game's `Cauldron2D.Client.Game` module through
a title, a lobby (worlds in columns in a scrolling window — name, the game's kind of
world if it gives one, players, map — the chosen one described beside them with its
players, redrawn as players come and go, on `Cauldron2D.World.Presence`; teams, and a
chat unless the game says `chat?: false`), settings and the world, holding the
player's `Cauldron2D.Input`, their `Cauldron2D.Audio` and their `Cauldron2D.World`
connection. The game supplies every name and every element the screens show: its title,
its actions and key presets, its worlds, how a view becomes a scene, the hud — rows under
the world, or a column beside it with rows under both — its sounds and music, the sink
its audio plays through, and any pages of its own reachable from the title. The client
supplies the flow between screens and the keys that drive it (`Esc` back, `q` title, `?`
hints, `^Q` quit — each replaceable or dropped by the game's `client_keys/0`; an `fps` key,
bound only by the game, shows the frames a second the world sends). A game with screens
of its own embeds the client in its own drafter app, started at the lobby (`start:
:lobby`) and driven through the client's callbacks; its `worlds/1` gets the mount props.
A game with a
`guide/0` — sections of entries, each an art, a name and a line — gets a guide screen on
`h` from the title and the lobby: the arts on a surface down the left beside the text,
scrolled with the arrows, the page keys, Home and End.

Settings — control preset and rebinding, pointer steering, effects and music levels,
pixels or glyphs — are kept per player under `$XDG_CONFIG_HOME/<game>/<player>.settings`
and, when the player has an account, in its props.

```elixir
Cauldron2D.Drafter.Server.start(game: MyGame.Client, port: 2222, web: {:my_game, MyGame.Web.Endpoint, 2280})
```

`Cauldron2D.Drafter.Server` starts the ssh daemon with the game's accounts (a sound
port each), the game's web endpoint and the beacon; the worlds are the game's, registered
with `Cauldron2D.Worlds`. `mix cauldron.input` measures drafter's input path from a
`DRAFTER_TRACE` log.

## Placements

On a kitty terminal whose cell size the session knows, the grid is one stored image sent
again only when its tiles change, and every mover is a placement of a sprite stored once
by `Cauldron2D.Drafter.Sprites.transmit/2` — about forty bytes per mover per frame, at
sub-cell pixel offsets. Elsewhere the movers are composited into one image per frame, as
below.

## Two renderings, one view

* **pixel** — `image/3` composites the viewport and hands drafter one image as a kitty /
  iTerm2 / sixel escape sequence. drafter owns placing and clearing it
* **text** — `render/2` draws two-cell glyphs in truecolour, from the same cells

The pixel path also returns blank strips, because the cells under an image still have to be
painted with something or the previous frame shows through the transparent parts of the art.

## Compression

kitty transmits are `compress: true` by default here. A tilemap is a handful of tiles stamped
hundreds of times, which is about as compressible as image data gets — measured at ~300× on a
full viewport, for roughly a millisecond of deflate. Pass `compress: false` for a terminal
whose kitty support is partial.

## License

MIT
