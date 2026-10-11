# Cauldron2D.Easel.Drafter

The atlas editor in the terminal, on [drafter](https://hexdocs.pm/drafter): the arts of a directory,
and one of them on a zoomed canvas with the palette, the tools and the frames beside it.
The pointer paints; every tool and colour has a key.

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_easel_drafter, "~> 0.2", only: :dev}
  ]
end
```

```
mix cauldron.easel priv/art --tile 16 --atlas my_game
```

```elixir
Drafter.run(Cauldron2D.Easel.Drafter, props: %{dir: "priv/art", tile: 16, atlas: :my_game})
```

A pixel is a block of cells in its colour, so it works in any terminal, over ssh
included. The pointer paints; every tool, colour and frame in the side panel is a
button; `?` lists every key on screen. `c` opens a colour picker — a chart of hues and
greys with the palette under it, chosen with the pointer or the arrows — and adds the
colour under the next free key; `i` is an eyedropper. With `--atlas`, `w` saves and
installs the directory as that atlas, and a game running in the same VM that subscribed
to it (`Cauldron2D.Atlas.subscribe/1`) redraws with the new art on its next frame.

Beside the canvas the picture is shown at actual size, drawn by the engine's own surface
widget the way a game draws it: through the terminal's graphics protocol (kitty, sixel,
iTerm) where the terminal has one, animated at the picture's rate; as its glyph where it
has not. `m` tiles it, for a picture meant to repeat.

On the arts screen `D` derives an art from the one chosen — `name = from ART; colour K
#rrggbb; flip h; over HAT 0 -2`, the line `Linocut.Derive` reads — kept in `atlas.txt`
and rebuilt from the drawing every time the atlas loads; `y` clones one as a picture of its
own. Draw the knight once; the red knight is a line.

`Cauldron2D.Easel.Drafter.Canvas` is the widget, usable in any drafter application:
`{:easel_canvas, [easel: easel, zoom: 4, on_paint: :paint]}`.
`Cauldron2D.Easel.Drafter.ActualSize` is the picture as an installed atlas for a
`Cauldron2D.Drafter.Surface` to draw.

This is a pixel-art tool: a picture is a palette of up to ninety colours and a grid of
keys, which is what `.pic` holds and what every renderer draws. A `.png` with more
colours than that is refused on load rather than quantised.

## The sector editor

`mix cauldron.sectors` opens `Cauldron2D.Easel.Drafter.SectorEditor` on a sector
document, creating it on the first save if it does not exist:

```
mix cauldron.sectors priv/maps/hall.json
mix cauldron.sectors priv/maps/hall.json --grid 16
```

`--grid` is the snap for a new document, in world units (default `32`). The document is a
`Cauldron2D.Easel.Sectors` map: rooms drawn as polygons on a grid, joined where they share
an edge, with heights, pictures and light set per room and per wall, and a history to undo
through.

## License

MIT
