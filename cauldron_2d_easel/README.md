# Cauldron2D.Easel

Editing a [`cauldron_2d`](https://hexdocs.pm/cauldron_2d) atlas as data: a picture is a palette, frames
of palette keys, the frame in hand and a history to undo through, and every operation on
it is a pure function.

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_easel, "~> 0.1"}
  ]
end
```

```elixir
easel = Cauldron2D.Easel.new(16, 16, palette: [{"R", "#c33"}, {"W", :white}])
easel = easel |> Cauldron2D.Easel.paint({3, 4}, "R") |> Cauldron2D.Easel.fill({0, 0}, "W")
easel = Cauldron2D.Easel.undo(easel)
:ok = Cauldron2D.Easel.save(easel, "priv/art/ship.pic")
```

| | |
|---|---|
| `Cauldron2D.Easel` | the document: paint, line, rect, fill, erase; flip, rotate, shift; the palette; frames at a rate; undo and redo; `.pic` and `.png` in and out |
| `Cauldron2D.Easel.Project` | an art directory: its arts, opening one, saving one, the manifest (`atlas.txt`) with each art's glyph, colour and rate, and installing the directory as an atlas |

The document is what a `.pic` file holds ([`Linocut.Pic`](https://hexdocs.pm/linocut)): palette lines, a
blank line, the frames separated by `---`. That makes an edit a change to a key in a
grid, a diff readable, and a recolouring a change to one palette line. A `.png` is the
frames side by side; reading one gives every distinct colour a key.

The front ends are separate packages, each holding an easel and drawing it:
[`cauldron_2d_easel_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter) in the terminal,
[`cauldron_2d_easel_web`](https://hexdocs.pm/cauldron_2d_easel_web) in a browser with LiveView, and
[`cauldron_2d_easel_kino`](https://hexdocs.pm/cauldron_2d_easel_kino) for looking at art in Livebook.

## License

MIT
