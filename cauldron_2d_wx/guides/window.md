# Running a game in a desktop window

`cauldron_2d_wx` shows a `cauldron_2d` game in a window drawn with wx. The window can join
a world in the same app or on a connected node, or a world on a server, over the same
WebSocket a browser uses.

The game is still one `Cauldron.Client.Game` module. The same module runs in a terminal
with [`cauldron_2d_drafter`](https://hexdocs.pm/cauldron_2d_drafter/terminal.html) and in a
browser with [`cauldron_2d_net`](https://hexdocs.pm/cauldron_2d_net/browser.html); here the
window reads it the same way, through the client modules of `cauldron_2d` and
`cauldron_core`.

## Opening the window

```elixir
Cauldron2D.Wx.Client.run(game: MyGame.Client, username: "alice")
```

`run/1` opens the window and returns `:ok` when the player closes it. A mix task is a good
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

| Option | Holds | Default |
| --- | --- | --- |
| `:game` | The client module. Required | — |
| `:username` | The player's name | `"player"` |
| `:props` | Given to the game's `worlds/1`, `pages/1`, `fronts/1` and `sink/1`, and may carry the launch's `:start` | `%{}` |
| `:link` | A function from a world to the link the view joins with | A local link to the world's process |
| `:size` | The window's size in pixels | `{1320, 800}` |
| `:scale` | Screen pixels a picture pixel takes | `1` |
| `:backdrop` | Drawn behind the screens, as `Cauldron2D.Wx.Text` takes it | None |

The window has a title screen, a lobby of worlds, settings, the world, a summary at the end
of a round, the guide and the game's own pages. The window draws and runs the game's own
title and summary (`fronts/1`) in place of its own, and the game's `start/0` decides where
the window opens. A function flow works as it does in the terminal client, so the window
opens on the title.

Settings — the key preset, the effects and music levels, whether the pointer aims, the
frame rate and the game's own options — are kept per player under
`Cauldron.Paths.config(home, "<player>.desktop.settings")`, `home` the game's
`Cauldron.Client.Game.home/1`. The game's menu changes them too.

## What the window has that a terminal does not

| The window | The terminal |
| --- | --- |
| Paints its canvas with `Cauldron2D.Draw` at `:scale` screen pixels per picture pixel, with no terminal involved | Needs a pixel protocol — kitty, iTerm2 or sixel — to show pixels, and falls back to glyphs without one |
| Draws the hud in a panel beside the picture (`:right`) or under it (`:bottom`), with its own width, colours and font | Draws the hud as rows in the same pane as the world |
| Draws its screens as text items at four sizes over a backdrop function, and an item carries an action a click sends | Draws its screens as cells, and a click arrives as a mouse event a widget reads |
| Gets a key press and a key release with its modifiers, always | Gets releases only where the terminal supports the kitty keyboard protocol |
| Reads this machine's game controllers through the `gamepad` package, `:controllers` on by default | Reads them only where the app itself runs: a session over ssh or telnet has its controller on its own machine |
| Shows a frame counter if asked, through `:on_stats` or `show_stats/2` | Shows the fps row under the world when the game binds the `fps` key |

The picture itself is the same one: `Cauldron2D.Draw`'s, so the game's layers, projections,
`:screen`, `:outlines` and menu look as they do in the terminal. A game does not choose
between the two front ends; it gets the same scene, drawn to a canvas instead of to cells.

The window is also its own process: `run/1` starts a wx application with `:wx.new/0`, opens
one frame titled with the game's `title/0` name, and destroys the application when the
frame closes.

## Input

wx reports keys as its own integer codes. `Cauldron2D.Wx.Keys` is the translation both ways:

```elixir
Cauldron2D.Wx.Keys.code(:left)
#=> 314

Cauldron2D.Wx.Keys.input_key(?A)
#=> :a
```

`input_key/1` answers a wx key code as the key `Cauldron.Input` names: the named keys
(`enter`, `escape`, `tab`, `backspace`, `delete`, the arrows, `home`, `end`, `page_up`,
`page_down`, `insert`, the shifts, controls and alts), `F1` to `F24`, letters as lower-case
letters, and other printable ASCII as itself. It answers `nil` for a key with no name of its
own. `code/1` goes the other way, takes a key spec — including `{:mouse, button}` and a
`{key, mods}` pair — and answers the wx code that presses it, or `nil` for a key wx has no
code for.

The window holds no keymap of its own. A key goes to the link as it goes down and as it goes
up, with the modifiers held, and the session on the far side reads it with the game's
keymaps and padmap, exactly as a browser's key does. The pointer's buttons, wheel and moves
go the same way, each with `at`, the pointer as fractions of the picture; the controllers'
events go as `Gamepad.Wire` events.

The keys a player uses are the client's, `Cauldron.Client.Keys.of/1`'s, so the game changes
them with `client_keys/0` once for every front end.

| Screen | Keys |
| --- | --- |
| Title | `Enter` plays, `s` settings, `h` guide, a page's key opens it, `Esc` or `q` quits |
| Lobby | `↑`/`↓`, `PgUp`/`PgDn`, `Home`/`End` pick, `Enter` joins, `w` watches, `t` a team, `s` settings, `h` guide, `c` chats, `Esc` back |
| Settings | `↑`/`↓` choose, `←`/`→` change, `Esc` back |
| World | The game's keys and the client's, through `Cauldron.Client.Stage` |
| Summary | `Enter` again or on, as the outcome's `:next` says, `Esc` to the lobby |
| Guide and pages | `↑`/`↓`, `Esc` back |

In a game with a chat, the hud panel lists the last messages of the world's room under the
hud rows, and the game's talk key opens a line there: typed into until `Enter` says it or
`Esc` drops it, the game's keys standing idle meanwhile.

## Playing on a server

By default the player joins the chosen world's process directly. `:link` is a function that
takes a world and answers the link to join it with, so a window can play on a server:

```elixir
{:ok, token} = Cauldron.Net.Remote.login("http://arcade:2280/api", "alice", "secret", false)

Cauldron2D.Wx.Client.run(
  game: MyGame.Client,
  username: "alice",
  link: fn world ->
    {:socket,
     url: "http://arcade:2280",
     token: token,
     topic: "world:#{world.id}",
     params: %{},
     atlas: :my_game}
  end
)
```

A `{:socket, opts}` link takes the options of `Cauldron.Net.Link.Socket`, and a `{:local,
opts}` link those of `Cauldron.Net.Link.Local`. Give the socket link `:atlas`, the game's
atlas name, when the server leaves drawing to its clients: the window then draws the scenes
it receives with its own atlas. A server that draws for its clients sends pictures, and the
window shows them without an atlas.

## A world in a window of your own

`Cauldron2D.Wx.View` is the panel the client draws the world on. It can go in any wx
window, without the client around it:

```elixir
wx = :wx.new()
frame = :wxFrame.new(wx, -1, ~c"My game", size: {1300, 700})
view = Cauldron2D.Wx.View.new(frame, on_go: fn to -> send(self(), {:go, to}) end)
:wxFrame.show(frame)

Cauldron2D.Wx.View.join(view, {:socket,
  url: "http://host:port",
  token: token,
  topic: "world:main",
  params: %{}
})
```

`join/3` takes `{:socket, opts}` or `{:local, opts}`, and its own options `:opening` — rows
of runs drawn centred on the canvas until the first picture arrives — and `:watching`, which
makes the arrow keys and a drag pan the view instead of reaching the world.

The view's other options set the canvas and the hud — `:size`, `:scale`, `:hud`,
`:hud_size`, `:hud_colours`, `:font` — and name the callbacks that follow the link:
`:on_over`, `:on_closed`, `:on_refused`, `:on_go`, `:on_settings` and `:on_world`.
`:on_key` and `:on_pad` are called while no link is joined, for a screen the owner draws
with `show/2`. `:controllers`, `:sound`, `:on_stats` and `:show_stats` set the controllers,
the sound and the frame counter.

While it runs, `configure/2` tells the link of settings changed beside the world, `pause/1`
pauses a world of the player's own, `levels/3` sets the effects and music levels, and
`show/2` shows a picture with no link joined, such as the game's title front. `leave/1`
ends the join.

`Cauldron2D.Wx.Text` is the panel the client draws its own screens on, and can be used
the same way:

```elixir
text = Cauldron2D.Wx.Text.new(frame, owner: self(), backdrop: &MyGame.Wx.stars/3)

Cauldron2D.Wx.Text.show(text, [
  {{:centre, 640}, 200, "DOTS", {127, 214, 255}, :title},
  {60, 300, "Enter  play", {228, 231, 243}, :big}
])
```

An item is `{x, y, text, colour, size}`, with `x` a left edge in pixels or `{:centre, x}`,
and an optional sixth element, an action a click on the item's text sends its owner.

## Requirements

The window is wxWidgets. The package lists `:wx` in its `extra_applications`, so the
Erlang/OTP the game runs on must be built with wx. OTP builds that leave it out — headless
distributions, some system packages, some container images — fail to start this package, so
no window opens. Ask the VM whether it has wx before anything else:

```
elixir -e 'IO.inspect(Code.ensure_loaded?(:wx))'
```

A `true` means the window can open. A machine with wx but no display — a server, a CI
runner — can load the module and still cannot show a frame, so the window is for a machine
someone is sitting at.

The package also has to be a dependency:

```elixir
def deps do
  [
    {:cauldron_2d_wx, "~> 0.4"}
  ]
end
```

## Where to go next

| You want to | Read |
| --- | --- |
| Play the same game in a terminal | [`cauldron_2d_drafter`'s guide](https://hexdocs.pm/cauldron_2d_drafter/terminal.html) |
| Play the same game in a browser | [`cauldron_2d_net`'s guide](https://hexdocs.pm/cauldron_2d_net/browser.html) |
| Understand the links and the sessions | [`cauldron_net`](https://hexdocs.pm/cauldron_net) |
| The view's own API | `Cauldron2D.Wx.View` |
| Draw the game | [`cauldron_2d`'s tutorial](https://hexdocs.pm/cauldron_2d/tutorial.html) |
