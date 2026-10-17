# Cauldron2D.Easel.Drafter

This package is the atlas editor in the terminal, built on [drafter](https://hexdocs.pm/drafter). It
lists the arts of a directory. It opens one on a zoomed canvas, with the palette, the
tools and the frames beside it. The pointer paints, and every tool and colour has a
key. The package also holds the sector map editor.

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:cauldron_2d_easel_drafter, "~> 0.3", only: :dev}
  ]
end
```

## Usage

Run the mix task on an art directory:

```
mix cauldron.easel priv/art --tile 16
mix cauldron.easel priv/art --tile 16 --art ship --atlas my_game
```

`--tile` is required. It is the tile size in pixels. `--art` opens that art at once.
`--atlas` names the atlas that saves install into.

To start the editor from code, pass the same options as mount props:

```elixir
Drafter.run(Cauldron2D.Easel.Drafter, props: %{dir: "priv/art", tile: 16, atlas: :my_game})
```

Each pixel is drawn as a block of cells in its colour. This works in any terminal,
over ssh too. The pointer paints. Every tool, colour and frame in the side panel is a
button. Press `?` to see every key.

* Tools: `b` brush, `l` line, `r` rectangle, `R` filled rectangle, `f` fill, `e` eraser,
  `i` eyedropper.
* `c` opens the colour picker. It shows a chart of hues and greys with the palette
  under it. Choose with the pointer or the arrows. The colour goes under the next free key.
* `o` shows the frame before as onion skin. `p` plays the frames.
* `u` undoes and `U` redoes.
* `s` saves. `w` saves and installs the directory as the atlas named by `--atlas`.

A game in the same VM can subscribe to that atlas with `Cauldron2D.Atlas.subscribe/1`.
It then redraws with the new art on its next frame.

The side panel shows the picture at actual size. It is drawn by
[`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter)'s surface widget, the same way a game
draws it. A terminal with graphics (kitty, sixel, iTerm2) shows the picture, animated at
its rate. Other terminals show its glyph. Press `m` to tile the picture, to check one
that repeats. Press `g` to set the glyph and colour the text renderer draws.

On the arts screen, press `D` to derive an art from the one chosen. You type a line
that `Linocut.Derive` reads, such as `name = from ART; colour K #rrggbb; flip h; over HAT 0 -2`.
The line is kept in `atlas.txt`. The derived art is rebuilt from the drawing every time
the atlas loads. Press `y` to clone an art into a picture of its own.

This is a pixel-art tool. A picture has a palette of up to ninety colours and a grid of
keys. That is what `.pic` holds and what every renderer draws. A `.png` with more
colours is refused on load. It is not quantised.

## The widgets

`Cauldron2D.Easel.Drafter.Canvas` is the canvas widget. Any drafter application can use
it. Call `Cauldron2D.Easel.Drafter.register_widgets/0` first, then add:

```elixir
{:easel_canvas, [id: :canvas, easel: easel, zoom: 4, onion: false, on_paint: :paint, flex: 1]}
```

A press or a drag sends the application `{:paint, %{x: x, y: y, phase: :start | :drag | :end}}`.

`Cauldron2D.Easel.Drafter.Swatches` is the colour chart widget, `:easel_swatches`.
`Cauldron2D.Easel.Drafter.ActualSize` installs the picture being edited as an atlas
with one art. A `Cauldron2D.Drafter.Surface` then draws it.

## The sector editor

Run `mix cauldron.sectors` on a sector document. It opens
`Cauldron2D.Easel.Drafter.SectorEditor`. If the file does not exist, the first save
creates it.

```
mix cauldron.sectors priv/maps/hall.json
mix cauldron.sectors priv/maps/hall.json --grid 16
```

`--grid` sets the snap for a new document, in world units. The default is `32`.

The document is a `Cauldron2D.Easel.Sectors` map. You draw rooms as polygons on a
grid. Rooms that share an edge are joined. Each room and wall has its own heights,
pictures and light. Edits can be undone. The plan from above is
`Cauldron2D.Easel.Drafter.Plan`. Beside it, `Cauldron2D.Sectors.View` draws a
first-person view. It uses `Cauldron2D.Easel.SectorArt`'s pictures, or the game's own
pictures when you pass them as the `:art` prop.

The keys:

* `m` switches between drawing and choosing.
* Drawing: press on the plan to add a corner. `Enter` closes the room. `Backspace` takes
  back a corner. `Esc` drops the room.
* Choosing: press on a room to pick it. The eye stands in that room.
* With a room picked: `f`/`F` lower or raise the floor, `c`/`C` the ceiling. `[`/`]`
  change the light. `t` sets the floor's picture, `T` the ceiling's and `w` the walls'.
  `x` removes the room.
* The eye: `i`/`k` move forward and back. `j`/`l` turn.
* The plan: arrows pan. `+`/`-` zoom.
* `u` undoes, `U` redoes, `s` saves, `^Q` quits.

## How it fits

The document and the art directory come from
[`cauldron_2d_easel`](https://hexdocs.pm/cauldron_2d_easel). This package draws them with
[drafter](https://hexdocs.pm/drafter) and [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter).
The same editor runs in a browser with
[`cauldron_2d_easel_web`](https://hexdocs.pm/cauldron_2d_easel_web), and in Livebook with
[`cauldron_2d_easel_kino`](https://hexdocs.pm/cauldron_2d_easel_kino).

## License

MIT
