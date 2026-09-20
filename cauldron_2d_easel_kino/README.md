# Cauldron2D.Easel.Kino

Cauldron2D art in Livebook: the atlas editor as a cell, and a picture, an art directory
as a sheet, or an animation, each as an image a cell shows.

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjaman%2Fcauldron%2Fmain%2Fcauldron_2d_easel_kino%2Fnotebooks%2Feasel.livemd)

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
as a surface. The badge opens it in Livebook; its setup cell installs the package from Hex
and it needs nothing else. Working from a checkout instead, give the setup cell a `path:` —
`{:cauldron_2d_easel_kino, path: "/absolute/path/to/cauldron_2d_easel_kino"}` — and
re-run it after editing the code.

| Notebook | | |
| --- | --- | --- |
| `notebooks/easel.livemd` | The tour: the editor cell, pictures as text and as code, an animated one, an art directory and its manifest, one drawing derived into many, the atlas installed and a surface composed from it | [![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjaman%2Fcauldron%2Fmain%2Fcauldron_2d_easel_kino%2Fnotebooks%2Feasel.livemd) |

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
