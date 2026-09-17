# Cauldron2D.Easel.Kino

Cauldron2D art in Livebook: the atlas editor as a cell, and a picture, an art directory
as a sheet, or an animation, each as an image a cell shows.

## Installation

In a notebook's setup cell:

```elixir
Mix.install([{:cauldron_2d_easel_kino, "~> 0.1"}])
```

```elixir
editor = Cauldron2D.Easel.Kino.Editor.new("priv/art/ship.pic", atlas: :game, tile: 16)
Cauldron2D.Easel.Kino.Editor.easel(editor)

Cauldron2D.Easel.Kino.image("priv/art/ship.pic", scale: 8)
Cauldron2D.Easel.Kino.sheet("priv/art", tile: 16, scale: 4)
Cauldron2D.Easel.Kino.animate("priv/art/flame.pic", scale: 8)
```

The editor cell paints with the pointer and has the tools, the palette, the frames, onion
skin, playback and undo of the other editors. Its **save** writes the file the cell was
opened on and, with `atlas:` and `tile:`, installs the directory as that atlas, so a game
running in the same notebook draws the change on its next frame. `easel/1` is the
document as it stands, for any later cell.

`notebooks/easel.livemd` walks through it: the editor on a blank picture and on a file, a
static tile and an animated one made with `Cauldron2D.Easel`, an art directory with its
manifest, derivations with `Linocut`, and the directory installed as an atlas and composed
as a surface. Open it in Livebook from this directory; its setup cell installs the package
by path.

`Cauldron2D.Easel.derive/3` makes a view from a picture by a line — `colour B #20c040;
flip h; over hat 0 -1` — and `Cauldron2D.Easel.Project.derive/3` keeps such a line in
`atlas.txt`, so one drawing is every costume and heading it needs.

This is a pixel-art tool: pictures are a palette of up to ninety colours and a grid of
keys, which is what `.pic` holds and what the terminal, the browser and the window draw.
A `.png` with more colours than that is refused on load rather than quantised.

The same editor in a browser outside Livebook is
[`cauldron_2d_easel_web`](https://hexdocs.pm/cauldron_2d_easel_web); in a terminal,
[`cauldron_2d_easel_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter).

## License

MIT
