# Cauldron2D.Wx

This package shows a `cauldron_2d` game in a desktop window drawn with wx. The window
can join a world in the same app or on a connected node. It can also join a world on a
server, over the same WebSocket a browser uses.

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:cauldron_2d_wx, "~> 0.4"}
  ]
end
```

You need an Erlang built with wx.

## Running a game

Your game implements `Cauldron.Client.Game` once. The same module runs in the
terminal with `Cauldron2D.Drafter.Client` from `cauldron_2d_drafter`. It runs in a
browser with `Cauldron2D.Net.Pages` from `cauldron_2d_net`. Here, call
`Cauldron2D.Wx.Client.run/1`:

```elixir
Cauldron2D.Wx.Client.run(game: MyGame.Client, username: "alice")
```

`run/1` opens the window and returns when the player closes it. A mix task is a good
place for it:

```elixir
defmodule Mix.Tasks.MyGame.Desktop do
  use Mix.Task

  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Cauldron2D.Wx.Client.run(game: MyGame.Client, username: Keyword.get(opts, :name, "player"))
  end
end
```

The window has a title screen, a lobby, settings, the world, a summary at the end of a
round, the guide and the game's own pages. It reads the game the way the terminal and
the browser do, through the modules of `cauldron_2d`:

* **The picture** is `Cauldron2D.Draw`'s, so the game's layers, projections, `:screen`,
  `:outlines` and menu look as they do in the terminal.
* **The game's own title and summary** (`fronts/1`) are drawn and run in place of the
  window's own (`Cauldron.Client.Fronts`).
* **Where the window opens** is the game's `start/0` (`Cauldron.Client.Start`). A
  function flow belongs to the terminal client, and the window opens on the title for it.
* **In the world**, the game's menu, its look and the client's keys (`client_keys/0`)
  work as in the terminal, through `Cauldron.Client.Stage`. Keys, the mouse and game
  controllers are read as every front end reads them (`Cauldron.Client.Controls`,
  `Cauldron.Client.Party`), by the game's keymaps and padmap.
* **The lobby** has a chat on `Cauldron.Chat`'s `:lobby` room, and the world's hud
  panel shows the world's room, in a game whose `chat?/0` is not `false`. The game's talk
  key opens a line in the world.
* **Settings** are the key preset, the effects and music levels, whether the pointer
  aims, the frame rate (the game's `frame_rates/1`), and the game's own options
  (`options/0`), which its menu can change too. They are kept per player under the
  game's `home/0`.

By default the player joins the chosen world's process directly. To play on a server,
pass `:link`. It is a function that takes a world and returns the link to join it with:

```elixir
{:ok, token} = Cauldron.Net.Remote.login("http://arcade:2280/api", "alice", "secret", false)

Cauldron2D.Wx.Client.run(
  game: MyGame.Client,
  username: "alice",
  link: fn world ->
    {:socket, url: "http://arcade:2280", token: token, topic: "world:#{world.id}", params: %{}, atlas: :my_game}
  end
)
```

Give the socket link `:atlas`, the game's atlas name, when the server leaves the drawing
to its clients (`Cauldron2D.Net.Drawing`): the window then draws the scenes it receives.
A server that draws for its clients sends pictures, and the window shows them.

`run/1` takes these other options:

* `:props` is given to the game's `worlds/1`, `pages/1`, `fronts/1` and `sink/1`, and
  may carry the launch's `:start`.
* `:size` is the window size. The default is `{1320, 800}`.
* `:scale` is how many screen pixels one picture pixel takes. The default is `1`.
* `:backdrop` is drawn behind the screens.

`Cauldron2D.Wx.Client` lists the keys of each screen.

## A world in a window of your own

`Cauldron2D.Wx.View` is the panel the client draws the world on. You can put it in any
wx window:

```elixir
wx = :wx.new()
frame = :wxFrame.new(wx, -1, ~c"My game", size: {1300, 700})
view = Cauldron2D.Wx.View.new(frame, on_go: fn to -> send(self(), {:go, to}) end)
:wxFrame.show(frame)
Cauldron2D.Wx.View.join(view, {:socket, url: "http://host:port", token: token, topic: "world:main", params: %{}, atlas: :my_game})
```

`join/3` takes `{:socket, opts}` with the options of `Cauldron.Net.Link.Socket`, or
`{:local, opts}` with the options of `Cauldron.Net.Link.Local`: `game:`, `world:`,
`name:` and `props:`. Its own options are `:opening`, rows shown until the first picture
arrives, and `:watching`, which makes the arrow keys and a drag pan the view.

The view holds no keymap. It sends keys as they go down and up, the mouse's buttons,
wheel and moves with the pointer as fractions of the picture, and each controller event
to the link, and the server side reads them with the game's keymaps and padmap. It tells
the link the pane, the tiles the canvas shows at zoom 1, whenever the canvas changes
size. It shows a picture the link sends, or draws a scene the link decodes with
`Cauldron2D.Draw`, with the server's overlay over it.

Options to `new/2`:

* `:size`, `:scale`, `:hud`, `:hud_size`, `:hud_colours` and `:font` set the canvas and
  the hud panel.
* `:on_over`, `:on_closed` and `:on_refused` are called at the end of a round, when the
  link ends and when the join is refused.
* `:on_go` is called with `:lobby`, `:settings` or `:title` when the game's menu or the
  client's keys send the player there; `:on_settings` with the player's settings when
  the game's menu changed them; `:on_world` with the new world's id when the world moved
  the player.
* `:on_key` and `:on_pad` are called with each key and controller button pressed while
  no link is joined, for a screen the owner draws with `show/2`.
* `:controllers` is whether the view reads this machine's game controllers. The default
  is `true`.
* `:sound`, `:on_stats` and `:show_stats` set the sound and the frame counter.

While it runs, `configure/2` tells the link of settings changed beside the world
(`:preset`, `:pointer`), `pause/1` pauses a world of the player's own, `levels/3` sets
the effects and music levels, and `show_stats/2` shows the frames and draws a second.
`show/2` shows a picture with no link joined, such as a game's title front.

| Module | What it does |
|---|---|
| `Cauldron2D.Wx.Client` | Opens the window around a game's worlds with `run/1`. |
| `Cauldron2D.Wx.Client.Screens` | Lays out the title, lobby, settings, summary, guide and pages as text items. |
| `Cauldron2D.Wx.View` | Shows a world and sends its raw input and pane to the link. Call `join/3` with a link and `leave/1` to go. |
| `Cauldron2D.Wx.Text` | Draws the screens around the worlds. Call `new/2`, then `show/2` with text items. It draws them over the game's backdrop and sends keys to its owner. |
| `Cauldron2D.Wx.Keys` | Turns a wx key code into the key `Cauldron.Input` names (`input_key/1`), and a key spec into a wx key code (`code/1`). |
| `Cauldron2D.Wx.Const` | Holds the wx constants the package uses. |

## How it fits

The window takes a link and shows what arrives on it. The links come from
`cauldron_net`: `Cauldron.Net.Link.Socket` over a WebSocket and
`Cauldron.Net.Link.Local` to a process. Both run the player's client on the far side
(`Cauldron.Net.Session`), so the window gets the same picture or scene, the same
menu, and the same reading of its input as a browser. That package also gives the speaker
(`Cauldron.Net.Sound`). The worlds, the atlas, the renderer and the
`Cauldron.Client.Game` behaviour come from `cauldron_2d`. Sound is the world's
`Cauldron.Audio`, played through `tuning_fork`.

## License

[AGPL-3.0-only](LICENSE). You may use, study, change and share it under the AGPL at
no cost.

A game or service whose source you do not publish needs a
[commercial license](COMMERCIAL.md).
