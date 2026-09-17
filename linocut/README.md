# Linocut

Pictures written in code, for games on [`cauldron_2d`](https://hexdocs.pm/cauldron_2d). What
[`tuning_fork`](https://hexdocs.pm/tuning_fork) is to sound, this is to sprites: notation in Elixir, pure
render functions, a disk cache, and a way to look at the result.

## Installation

```elixir
def deps do
  [
    {:linocut, "~> 0.1"}
  ]
end
```

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
```

| | |
|---|---|
| `Linocut.sprite/3` | a picture with a palette legend, `.` and space transparent |
| `Linocut.outline/2` | a filled or stroked shape from its points, `x` right and `y` up |
| `Linocut.headings/3` | the shape at every heading, `0` pointing right, turning counter-clockwise |
| `Linocut.recolour/2`, `tint/3`, `scale/2` | derivations on any raster |
| `Linocut.Derive` | a picture from another by a line on its keys: `from knight; colour C #c02020; flip h; over hat 0 -2` |
| `Linocut.Pic` | the `.pic` file: a palette, a blank line, the picture; frames separated by `---` |
| `Linocut.Strip` | frames at a rate, looping |
| `Linocut.Cache` | rasters rendered once, kept under `~/.cache/linocut` |
| `Linocut.Preview` | a sheet of many rasters, terminal output, PNG |

Every result is a `FrenchCurve.Raster`, which `Cauldron2D.Atlas.put/4` takes as it is.

## Deriving

A `.pic` is keys, and its keys mean something: `C` is the cloak whatever colour it is.
So a second view is a line, not a second drawing:

```
from knight; colour C #c02020            the same knight in red
from knight; flip h                       facing the other way
from knight; over hat 0 -2                with a hat on
from walk; frame 3                        one frame of an animation
```

`Linocut.Derive.derive/2` runs such a line against a function that gives each name's
text; `Cauldron2D.Atlas.load/3` reads the same lines from the fifth field of `atlas.txt`
and builds the derived arts after the drawn ones. The operations work on the text of the
picture — reversing a row, transposing the grid, rewriting a palette line — so nothing is
rendered until the atlas is built, and a derived picture is a picture like any other.

## Looking at it

```bash
mix linocut.view examples/ship.exs                   # in this terminal, pixels or braille
mix linocut.view examples/ship.exs --scale 3 --columns 8
```

The script's last expression is a raster, a list of them, or a strip.

## License

MIT
