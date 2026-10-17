# Linocut

Linocut makes pictures from code and from files, for games on
[`cauldron_2d`](https://hexdocs.pm/cauldron_2d). It does for sprites what
[`tuning_fork`](https://hexdocs.pm/tuning_fork) does for sound. You write the picture as
notation in Elixir. Pure functions render it. A disk cache keeps the result, and a mix
task shows it in the terminal.

## Where it fits

Every result is a `FrenchCurve.Raster` from [`french_curve`](https://hexdocs.pm/french_curve).
`Cauldron2D.Atlas.put/4` takes one as it is. `cauldron_2d` reads an art directory's
`.pic` files and `Linocut.Derive` lines when it loads an atlas. The easel editors edit the
same `.pic` files: [`cauldron_2d_easel`](https://hexdocs.pm/cauldron_2d_easel) and its
terminal, browser and Livebook front ends.

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:linocut, "~> 0.3"}
  ]
end
```

## Usage

```elixir
ship =
  Linocut.sprite("""
  ..RR..
  .RWWR.
  RRWWRR
  """, R: "#c33", W: :white)

headings = Linocut.headings([{15, 0}, {-8, 8}, {-8, -8}], 64, size: {16, 16}, fill: "#e8e8e8")
red_team = Linocut.recolour(ship, %{{204, 51, 51, 255} => {51, 51, 204, 255}})
spin = Linocut.Strip.new(headings, 30)

atlas = Cauldron2D.Atlas.put(atlas, :ship, ship)
```

## What is here

| Name | What it does |
|---|---|
| `Linocut.sprite/3` | Draws a picture from text and a palette legend. `.` and space are transparent. |
| `Linocut.outline/2` | Draws a filled or stroked shape from its points. `x` goes right and `y` goes up. |
| `Linocut.headings/3` | Draws the shape at every heading. Heading `0` points right, and headings turn counter-clockwise. |
| `Linocut.recolour/2`, `tint/3`, `scale/2`, `squash/3`, `flip/2`, `rotate/2`, `transform/3` | Make a new raster from any raster. |
| `Linocut.frames/2` | Cuts a raster into frames of one size. |
| `Linocut.load/2`, `Linocut.pic/2` | Read a `.png` or `.pic` file, or `.pic` text, into a raster. |
| `Linocut.Palette` | Reads colours: `"#c33"`, `:cyan`, `{r, g, b}` or `{r, g, b, a}`. |
| `Linocut.Font` | Writes names, numbers and notes on a picture in a three-by-five pixel font. |
| `Linocut.Png` | Reads PNG files into a raster. |
| `Linocut.Derive` | Makes a picture from another with one line of operations on its keys, such as `from knight; colour C #c02020; flip h`. |
| `Linocut.Pic` | Reads and writes the `.pic` file. A `.pic` is a palette, a blank line, then the picture. Frames are separated by `---`. |
| `Linocut.Strip` | Plays frames at a rate, looping. |
| `Linocut.Cache` | Renders rasters once and keeps them under `~/.cache/linocut`. |
| `Linocut.Preview` | Lays many rasters on one sheet. It writes the sheet to the terminal or to a PNG. |
| `Linocut.Quantise` | Reduces a picture to a small palette, chosen by median cut over its opaque pixels. |
| `Linocut.Sheet` | Cuts a sprite sheet into frames. It finds them between blank rows and blank columns. |
| `Linocut.Frames` | Lines up the frames of one animation on one canvas, standing on the same floor. It writes them as a `.pic` with a shared palette. |
| `Linocut.Pose` | Holds a figure's joints. It draws the OpenPose skeleton that a ControlNet reads. |
| `Linocut.Resample` | Redraws a picture at another size, by area or by nearest pixel. |
| `Linocut.Seam` | Makes a picture repeat without a visible join. It fades the far edge into the near one. |
| `mix linocut.view` | Shows pictures in the terminal (see below). |
| `mix linocut.import` | Turns an image file into a `.pic` at a chosen size and palette. |
| `mix linocut.sheet` | Cuts a sprite sheet into the frames of one `.pic`. |
| `mix linocut.join` | Joins separately drawn pictures into the frames of one `.pic`. |
| `mix linocut.pose` | Writes OpenPose skeletons for an animation cycle, one PNG a frame. |

## Deriving

A `.pic` is made of keys, and each key means something. `C` is the cloak, whatever colour
it is. So a second view of a picture is one line, not a second drawing:

```
from knight; colour C #c02020            the same knight in red
from knight; flip h                       facing the other way
from knight; over hat 0 -2                with a hat on
from walk; frame 3                        one frame of an animation
```

The other operations are `swap KEY KEY`, `turn 90|180|270`, `shift DX DY`, `scale N` and
`reverse`. `reverse` puts the frames in the other order.

`Linocut.Derive.derive/2` runs a line. It takes a function that gives the text behind
each name. `Cauldron2D.Atlas.load/3` reads the same lines from the fifth field of
`atlas.txt`. It builds the derived arts after the drawn ones.

The operations work on the text of the picture, not its pixels. Nothing is rendered
until the atlas is built. A derived picture is a picture like any other.

## Looking at it

```bash
mix linocut.view ship.exs
mix linocut.view priv/art
mix linocut.view ship.exs --scale 3 --columns 8 --protocol braille
```

`mix linocut.view` shows pictures in this terminal. Give it a script whose last
expression is a raster, a list of rasters or a strip. You can also give it a `.png` or
`.pic` file, or a directory of them. `--protocol` picks `kitty`, `iterm2`, `sixel` or
`braille`; by default it is detected. The example script is in
[`examples`](https://github.com/jaman/cauldron/tree/main/linocut/examples).

## License

MIT
