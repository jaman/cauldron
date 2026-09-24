# Cauldron2D.Wx

A `cauldron_2d` world in a wx window, joined over the web wire (a Phoenix channel on a
WebSocket), through a process on this or a connected node, or in the same app.
`CAULDRON_WX_DESIGN.md` at the repository root is the design.

## Installation

```elixir
def deps do
  [
    {:cauldron_2d_wx, "~> 0.1"}
  ]
end
```

| module | what it is |
|---|---|
| `Cauldron2D.Wx.Client` | the window around the worlds — title, lobby, settings, world, summary, guide, the game's pages — from a `Cauldron2D.Client.Game`; `run/1` opens it |
| `Cauldron2D.Wx.Keys` | a game's keymap as wx key codes |
| `Cauldron2D.Wx.View` | the panel: canvas, hud where the game wants it, keys, pointer, sound; `join/2` with a link, `leave/1`, `levels/3`, `pointer/2`, `show_stats/2` (frames and draws a second) |
| `Cauldron2D.Wx.Text` | a canvas for the screens around the worlds: text items drawn as a game draws them over a backdrop of the game's, keys handed to the owner |
| `Cauldron2D.Wx.Input` | what the player holds and aims at |
| `Cauldron2D.Wx.Painter` | where tiles and movers land on the canvas |
| `Cauldron2D.Wx.Sheet` | the sprite sheet as bitmaps |
| `Cauldron2D.Wx.Const` | the wx constants used |

The links to a world (`Cauldron2D.Net.Link.Socket` over a WebSocket, `Link.Local` to
a process), the wire in Elixir (`Cauldron2D.Net.Wire`) and the speaker
(`Cauldron2D.Net.Sound`) are `cauldron_2d_net`'s; the view takes a link and draws.

```elixir
wx = :wx.new()
frame = :wxFrame.new(wx, -1, ~c"My game", size: {1300, 700})
view = Cauldron2D.Wx.View.new(frame, keymap: %{?A => :left, ?D => :right, 32 => :act}, steering: [:left, :right])
:wxFrame.show(frame)
Cauldron2D.Wx.View.join(view, {:socket, url: "http://host:port", token: token, topic: "world:main", params: %{}})
```

A game implements `Cauldron2D.Client.Game` once and `Cauldron2D.Wx.Client` runs it;
a game with screens of its own draws them on `Cauldron2D.Wx.Text`, which draws whatever
items it is given and reports keys, with the world on `Cauldron2D.Wx.View`. The
view's sizes, hud placement and colours are options; the canvas clears to the sheet's
void colour. Needs an Erlang built with wx. Tests cover the wire, the input, the painter and the local link; the window itself
is exercised by hand.

## License

MIT
