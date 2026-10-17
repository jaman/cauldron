# Cauldron2D.Wx

This package shows a `cauldron_2d` game in a desktop window drawn with wx. The window
can join a world in the same app or on a connected node. It can also join a world on a
server, over the same WebSocket a browser uses.

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:cauldron_2d_wx, "~> 0.3"}
  ]
end
```

You need an Erlang built with wx.

## Running a game

Your game implements `Cauldron2D.Client.Game` once. The same module runs in the
terminal with `Cauldron2D.Drafter.Client` from `cauldron_2d_drafter`. It runs in a
browser with `Cauldron2D.Net.Pages` from `cauldron_2d_net`. Here, call
`Cauldron2D.Wx.Client.run/1`:

```elixir
Cauldron2D.Wx.Client.run(game: MyGame.Client, username: "alice")
```

`run/1` opens the window and returns when the player closes it. The window has a
title screen, a lobby, settings, the world, a summary at the end of a round, the guide
and the game's own pages.

By default the player joins the chosen world's process directly. To play on a server,
pass `:link`. It is a function that takes a world and returns the link to join it with:

```elixir
{:ok, token} = Cauldron2D.Net.Remote.login("http://arcade:2280/api", "alice", "secret", false)

Cauldron2D.Wx.Client.run(
  game: MyGame.Client,
  username: "alice",
  link: fn world ->
    {:socket, url: "http://arcade:2280", token: token, topic: "world:#{world.id}", params: %{}}
  end
)
```

`run/1` takes these other options:

* `:props` is given to the game's `worlds/1`, `pages/1` and `sink/1`.
* `:size` is the window size. The default is `{1320, 800}`.
* `:scale` is how many screen pixels one sheet pixel takes. The default is `2`.
* `:backdrop` is drawn behind the screens.

`Cauldron2D.Wx.Client` lists the keys of each screen.

## A world in a window of your own

`Cauldron2D.Wx.View` is the panel the client draws the world on. You can put it in any
wx window:

```elixir
wx = :wx.new()
frame = :wxFrame.new(wx, -1, ~c"My game", size: {1300, 700})
view = Cauldron2D.Wx.View.new(frame, keymap: %{?A => :left, ?D => :right, 32 => :act}, steering: [:left, :right])
:wxFrame.show(frame)
Cauldron2D.Wx.View.join(view, {:socket, url: "http://host:port", token: token, topic: "world:main", params: %{}})
```

`join/2` takes `{:socket, opts}` with the options of `Cauldron2D.Net.Link.Socket`. It
also takes `{:local, opts}` with the options of `Cauldron2D.Net.Link.Local`: `game:`,
`world:`, `name:` and `props:`. Options to `new/2` set the view's size, where the hud
goes, its colours, zooming and the pointer. Other options are callbacks for the end of
a round, a closed link and a refused join. The canvas clears to the sheet's void
colour.

| Module | What it does |
|---|---|
| `Cauldron2D.Wx.Client` | Opens the window around a game's worlds with `run/1`. |
| `Cauldron2D.Wx.View` | Draws a world and reads its keys, pointer and sound. Call `join/2` with a link and `leave/1` to go. `pause/1`, `levels/3`, `keymap/2`, `pointer/2` and `zoom/2` change it while it runs. `show_stats/2` shows frames and draws a second. |
| `Cauldron2D.Wx.Text` | Draws the screens around the worlds. Call `new/2`, then `show/2` with text items. It draws them over the game's backdrop and sends keys to its owner. |
| `Cauldron2D.Wx.Keys` | Turns a game's keymap into wx key codes with `wx_keymap/1`. |
| `Cauldron2D.Wx.Input` | Tracks what the player holds and aims at. |
| `Cauldron2D.Wx.Painter` | Works out where tiles, movers and labels go on the canvas. |
| `Cauldron2D.Wx.Sheet` | Holds the sprite sheet as bitmaps. |
| `Cauldron2D.Wx.Const` | Holds the wx constants the package uses. |

## How it fits

The window takes a link and draws what arrives on it. The links come from
`cauldron_2d_net`: `Cauldron2D.Net.Link.Socket` over a WebSocket and
`Cauldron2D.Net.Link.Local` to a process. That package also gives the wire format
(`Cauldron2D.Net.Wire`) and the speaker (`Cauldron2D.Net.Sound`). The worlds, the atlas
and the `Cauldron2D.Client.Game` behaviour come from `cauldron_2d`. Sound is the world's
`Cauldron2D.Audio`, played through `tuning_fork`.

## License

MIT
