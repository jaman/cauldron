# Cauldron2D.Easel

This package edits [`cauldron_2d`](https://hexdocs.pm/cauldron_2d) art as data. A picture is a palette
and frames of palette keys. The easel also holds the frame in hand and a history to undo
through. Every operation on it is a pure function. The terminal, browser and Livebook
editors are built on it, and a game or a script can call it directly to make or change
art.

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:cauldron_2d_easel, "~> 0.3"}
  ]
end
```

## Usage

Make a picture, paint it, and save it:

```elixir
easel = Cauldron2D.Easel.new(16, 16, palette: [{"R", "#c33"}, {"W", :white}])
easel = easel |> Cauldron2D.Easel.paint({3, 4}, "R") |> Cauldron2D.Easel.fill({0, 0}, "W")
easel = Cauldron2D.Easel.undo(easel)
:ok = Cauldron2D.Easel.save(easel, "priv/art/ship.pic")
```

Open an art directory, change an art, and install the directory as an atlas:

```elixir
project = Cauldron2D.Easel.Project.open("priv/art", tile: 16)
Cauldron2D.Easel.Project.arts(project)
{:ok, easel} = Cauldron2D.Easel.Project.load(project, :ship)
{:ok, project} = Cauldron2D.Easel.Project.save(project, :ship, easel)
{:ok, :my_game} = Cauldron2D.Easel.Project.install(project, :my_game)
```

`install/2` builds the atlas with `Cauldron2D.Atlas.load/3` and installs it. A game in
the same VM can subscribe to the atlas with `Cauldron2D.Atlas.subscribe/1`. It then draws
the new art on its next frame.

| Module | What it does |
|---|---|
| `Cauldron2D.Easel` | Holds one picture being edited. It paints, draws lines and rectangles, fills and erases. It flips, rotates and shifts frames. It adds, sets, renames and removes palette colours. It adds, duplicates, deletes, moves and selects frames, and sets their rate. It undoes and redoes. `derive/3` makes a new picture from a `Linocut.Derive` line. It reads and writes `.pic` and `.png`. |
| `Cauldron2D.Easel.Project` | Works on an art directory. It lists the arts, and loads, saves, creates and clones them. It derives an art from another by a line in the manifest, `atlas.txt`. The manifest also holds each art's glyph, colour and rate. `install/2` installs the directory as an atlas. |
| `Cauldron2D.Easel.View` | Turns an easel into what a browser canvas draws. That is the frame in hand as CSS colours, the onion-skin frame, the palette, and the frame count and rate. The LiveView and Livebook editors send it to their scripts. |
| `Cauldron2D.Easel.Sectors` | Holds a sector map being edited. You draw rooms as polygons on a grid. Rooms that share an edge are joined. Each room and wall has its own heights, pictures and light. Edits can be undone. `to_map/2` gives the `Cauldron2D.Sectors` map a game plays. |
| `Cauldron2D.Easel.SectorArt` | Gives pictures for previewing a sector map that has no game art yet. The palette is sixteen hues in sixteen shades. The wall, floor and ceiling textures are drawn from it. They come as a `Cauldron2D.Sectors.Pictures` set. |

The document is what a `.pic` file holds ([`Linocut.Pic`](https://hexdocs.pm/linocut)). It is palette
lines, a blank line, and then the frames separated by `---`. An edit changes a key in a
grid. A recolouring changes one palette line. A key is one character, and `.` is
transparent. A `.png` holds the frames side by side. Reading one gives every distinct
colour its own key. There are ninety keys, so a `.png` with more colours is refused.

## How it fits

Each editor is its own package that holds an easel and draws it:

* [`cauldron_2d_easel_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter) runs in the terminal and also has the sector editor.
* [`cauldron_2d_easel_web`](https://hexdocs.pm/cauldron_2d_easel_web) runs in a browser with LiveView.
* [`cauldron_2d_easel_kino`](https://hexdocs.pm/cauldron_2d_easel_kino) runs in Livebook.

The editors install the `Cauldron2D.Atlas` a game draws from. The terminal renderer in
[`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter) draws the atlas directly.
[`cauldron_2d_net`](https://hexdocs.pm/cauldron_2d_net) makes a sprite sheet from it. The browser and the
window in [`cauldron_2d_wx`](https://hexdocs.pm/cauldron_2d_wx) draw that sheet.

## License

MIT
