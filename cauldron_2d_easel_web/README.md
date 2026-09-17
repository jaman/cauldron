# Cauldron2D.Easel.Web

The atlas editor in a browser, with LiveView: a game forwards a path in its router and
gets the arts of a directory and an editor for each, with its own layout and scripts.

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_easel_web, "~> 0.1", only: :dev}
  ]
end
```

```elixir
import Cauldron2D.Easel.Web.Router

scope "/" do
  pipe_through :browser
  easel "/easel", dir: "priv/art", tile: 16, atlas: :my_game
end
```

The document is a `Cauldron2D.Easel` held in the LiveView; the browser draws it on a
canvas (`priv/static/easel.js`) and sends back where the pointer paints. Tools, colours,
frames, undo, the text renderer's glyph and a save that installs the atlas are buttons
and keys. The endpoint needs the LiveView socket at `/live`, as a Phoenix application
has.

## License

MIT
