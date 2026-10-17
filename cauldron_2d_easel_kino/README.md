# Cauldron2D.Easel.Kino

This package shows Cauldron2D art in Livebook. It puts the atlas editor in a cell. It
also shows a picture, an art directory as one sheet, an animation, or a camera moving
across parallax layers.

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fraw.githubusercontent.com%2Fjaman%2Fcauldron%2Fmain%2Fcauldron_2d_easel_kino%2Fnotebooks%2Feasel.livemd)

## Installation

Add the package in a notebook's setup cell:

```elixir
Mix.install([{:cauldron_2d_easel_kino, "~> 0.3"}])
```

## Usage

```elixir
editor = Cauldron2D.Easel.Kino.Editor.new("priv/art/ship.pic", atlas: :game, tile: 16)
Cauldron2D.Easel.Kino.Editor.easel(editor)

Cauldron2D.Easel.Kino.image("priv/art/ship.pic", scale: 8)
Cauldron2D.Easel.Kino.sheet("priv/art", tile: 16, scale: 4)
Cauldron2D.Easel.Kino.animate("priv/art/flame.pic", scale: 8)
```

`Cauldron2D.Easel.Kino.Editor.new/2` takes a `.pic` or `.png` path, or a
`Cauldron2D.Easel`. The editor cell paints with the pointer. It has the same tools,
palette, frames, onion skin, playback and undo as the other editors.

Its **save** button writes the file the cell was opened on, or the `:save` path. With
`:atlas` and `:tile`, it then installs that file's directory as the atlas. A game running
in the same notebook draws the change on its next frame. `:zoom` sets how many screen
pixels show one picture pixel. The default is `16`. Call `easel/1` to get the document
as it stands in a later cell.

The other functions of `Cauldron2D.Easel.Kino`:

* `image/2` shows one picture. A picture is a `Cauldron2D.Easel`, a `FrenchCurve.Raster`,
  or the path of a `.pic` or `.png`. `:scale` enlarges every pixel. The default is `4`.
* `sheet/2` shows every art of a directory, or of a `Cauldron2D.Atlas`, on one sheet.
  `Cauldron2D.Sheet` packs it. `:tile` is required for a directory.
* `animate/2` shows an easel's frames in turn. It plays at the easel's rate, or at `:fps`.
* `parallax/3` moves a camera across `Cauldron2D.Parallax.Layer`s. It takes the options
  of `Cauldron2D.Parallax.Preview.frames/3`, plus `:zoom` and `:fps`.
* `png/2` returns a picture's PNG bytes at a scale.

`Cauldron2D.Easel.derive/3` makes a new picture from one by a line, such as
`colour B #20c040; flip h; over hat 0 -1`. `Cauldron2D.Easel.Project.derive/3` keeps
such a line in `atlas.txt`. One drawing can then give every recolouring and heading the
game needs.

This is a pixel-art tool. A picture has a palette of up to ninety colours and a grid of
keys. That is what `.pic` holds and what the terminal, the browser and the window draw.
A `.png` with more colours is refused on load. It is not quantised.

## The notebook

`notebooks/easel.livemd` is a tour. It opens the editor on a blank picture and on a
file. It writes pictures as text and as code, and makes an animated one. It shows an
art directory and its manifest. It derives many pictures from one drawing with
`Linocut`. Last, it installs the directory as an atlas and composes a surface from it.

The badge above opens the notebook in Livebook. Its setup cell installs the package from
Hex, and it needs nothing else. To run it from a checkout, give the setup cell
`{:cauldron_2d_easel_kino, path: "/absolute/path/to/cauldron_2d_easel_kino"}` instead.

## How it fits

The document and the art directory come from
[`cauldron_2d_easel`](https://hexdocs.pm/cauldron_2d_easel). The atlas it installs is the
[`cauldron_2d`](https://hexdocs.pm/cauldron_2d) `Cauldron2D.Atlas` a game draws from. The same
editor runs in a browser outside Livebook with
[`cauldron_2d_easel_web`](https://hexdocs.pm/cauldron_2d_easel_web), and in a terminal with
[`cauldron_2d_easel_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter).

## License

MIT
