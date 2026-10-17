# Cauldron2D.Easel.Web

This package is the atlas editor in a browser, built with LiveView. A game mounts it at
a path in its Phoenix router. The editor lists the arts of a directory and edits each
one. It brings its own layout and scripts.

## Installation

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:cauldron_2d_easel_web, "~> 0.3", only: :dev}
  ]
end
```

## Usage

Add the editor to the game's router:

```elixir
import Cauldron2D.Easel.Web.Router

scope "/" do
  pipe_through :browser
  easel "/easel", dir: "priv/art", tile: 16, atlas: :my_game
end
```

`:dir` and `:tile` are required. `:atlas` names the atlas that saves install into.
Without it, saves only write the files.

The scope must fetch the session. A `:browser` pipeline does this. The endpoint needs
the LiveView socket at `/live`:

```elixir
socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
```

Open `/easel` to see the arts. Open `/easel/<art>` to edit one. The editor serves its
own scripts and stylesheet under `/easel/assets`, so it does not need the game's assets.

The LiveView, `Cauldron2D.Easel.Web.EditorLive`, holds the `Cauldron2D.Easel`. The
browser draws it on a canvas and sends back where the pointer paints. Every tool is a
button and a key:

* Tools: `b` brush, `l` line, `r` rectangle, `R` filled rectangle, `f` fill, `e` eraser.
* `1`–`9` pick a colour.
* `h`/`v` flip, `t`/`T` turn, and the arrows shift the frame.
* `,`/`.` go to the frame before or after. `a` adds a frame, `d` duplicates it and `x`
  drops it.
* `o` shows onion skin. `p` plays the frames.
* `u` undoes and `U` redoes.
* `s` saves. `w` saves and installs the atlas.

A form sets the glyph and colour the text renderer draws.

## How it fits

The document and the art directory come from
[`cauldron_2d_easel`](https://hexdocs.pm/cauldron_2d_easel). A save with `:atlas` installs the
directory as that `Cauldron2D.Atlas`. A game in the same VM that subscribed to the atlas
draws the new art on its next frame. The same editor runs in a terminal with
[`cauldron_2d_easel_drafter`](https://hexdocs.pm/cauldron_2d_easel_drafter), and in Livebook with
[`cauldron_2d_easel_kino`](https://hexdocs.pm/cauldron_2d_easel_kino).

## License

MIT
