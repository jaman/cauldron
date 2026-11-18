# Running a game in a terminal

`cauldron_2d_drafter` puts a [`cauldron_2d`](https://hexdocs.pm/cauldron_2d/tutorial.html)
game in a terminal, through [drafter](https://hexdocs.pm/drafter/design_notes.html). The
game is written once, as a `Cauldron.Client.Game`, and this package runs it through the
screens a player sees: the title, the lobby, the settings, the world and the summary.

The whole front end is `Cauldron2D.Drafter.Client`, a drafter application. Starting it is
one call.

## The shortest run

```elixir
Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

Drafter.run(Cauldron2D.Drafter.Client,
  props: %{game: MyGame.Client, username: "alice"}
)
```

`Drafter.run/2` takes an app module and its options. `:props` is the map the client's
`mount/1` receives. The world is drawn by `Cauldron2D.Drafter.Surface`, a widget the
registry must know about before the client mounts; the server, the test helper and the
package's own runner register it themselves.

`Drafter.run/2` blocks until the player leaves. A standalone run halts the VM on the way
out unless it is given `halt_on_exit: false`. Called from an application that is already
running, it pushes the client as a nested session and returns to its caller when that
session stops.

## From a mix task

`Cauldron2D.Drafter.Play.run/3` starts the application, registers the surface, runs the
client and passes flags through:

```elixir
defmodule Mix.Tasks.MyGame do
  use Mix.Task

  def run(argv), do: Cauldron2D.Drafter.Play.run(MyGame.Client, argv, name: "alice")
end
```

`mix my_game --name bob --mute` sets the player's name and turns sound off. The flags are
`--name`, `--mute` / `--no-mute`, `--picture` and `--trace`. Each flag becomes the mount
prop of the same name, so it wins over the game's saved launch values, the environment and
the defaults. `mix cauldron.play MyGame.Client` runs any game's client this way without
writing a task.

`Play.run/3`'s own `:before` option is a function of no arguments, run once the application
has started and before the client opens — where a game registers its worlds.

## Mount props

| Prop | Holds | Default |
| --- | --- | --- |
| `:game` | The `Cauldron.Client.Game` module. Required | — |
| `:username` | The player's name, and the key their settings are saved under | `"player"` |
| `:picture` | How a game's own picture reaches the terminal | The look's, else `native:2,swap` |
| `:start` | The flow, over the game's `start/0` | The game's, else `:lobby` |
| `:sink` | The `Cauldron.Audio.Sink` the player's sound plays through | The game's `sink/1`, else the speaker or the session's tunnel |
| `:mute` | `true` plays no sound | `false` |
| `:settings` | A settings map, as the client's `to_props/1` makes one | The game's first preset |
| `:accounts` | The `Drafter.Accounts` server settings are saved to | None |
| `:kind` | The kind of client, the key its settings are kept under | `:terminal` |
| `:trace` | A file to write `Cauldron.Trace` events to | None |

Every other prop belongs to the game, and is read by its `sink/1`, `pages/1` and
`worlds/1`. `:picture`, `:mute` and `:trace` follow `Cauldron.Launch`'s order when their
prop is missing: the game's saved launcher values, then `CAULDRON_PICTURE`,
`CAULDRON_MUTE` and `CAULDRON_TRACE`, then `config :cauldron_2d_drafter`, then the default.

## Where the player starts

The game's `start/0`, or the `:start` prop over it, chooses the flow.

| Flow | What the player sees |
| --- | --- |
| `:lobby` | The title, then the lobby, then a world |
| `{:lobby, title: false}` | The lobby first; back from it stops the client |
| `{:play, id}` | Straight into world `id` of `worlds/1`; `:first` is the first listed |
| `{:play, id, title: true}` | The title, then that world; back returns to the title |
| a function of the client's state | A flow of the game's own: `enter/3`, `to_lobby/1`, `to_title/1`, `to_guide/1` |

A world whose `world` is `{module, opts}` is the player's alone: the client starts a
`Cauldron.World` when they join and stops it when they leave, and `p` pauses it. A screen
the game draws itself through its `fronts/1` is open from the client's first frame, so the
client's own version of that screen never appears in its place.

## The setup page

`Cauldron2D.Drafter.Launcher` is a page shown before the game starts. The player sets what
the game needs before it can run — where its data is, the skill, how it is drawn — and
Play saves the choices, so later runs start straight away.

```elixir
fields = [
  %{key: :dir, label: "Game folder", kind: {:path, &MyGame.Assets.check/1},
    discover: &MyGame.Assets.discover/0, hint: "the folder holding the game's files"},
  %{key: :skill, label: "Skill", kind: {:choice, [{1, "easy"}, {2, "normal"}]}, default: 2},
  Cauldron2D.Drafter.Launcher.drawing_field()
]

case Cauldron2D.Drafter.Launcher.choose(MyGame.Client, fields, player: "alice") do
  {:ok, values} -> start_the_game(values)
  :quit -> :ok
end
```

A field is a map with `:key`, `:label` and `:kind`, and optionally `:default`, `:discover`
and `:hint`. A `:kind` is `{:path, check}`, where `check` answers `:ok` or
`{:error, text}`, `{:choice, [{value, text}]}`, or `:text`.

`choose/3` works out each value from the run's `:overrides` (command-line flags), then what
was saved, then `:discover`, then `:default`. It shows the page when nothing has been saved,
when a path no longer passes its check, or when `launcher: true` asks for it. The values are
saved in `$XDG_CONFIG_HOME/<home>/launcher.config`, `<home>` the game's
`Cauldron.Client.Game.home/1`. Overrides that skip the page are not saved.

The `:drawing` field is also written into the player's settings when `:player` is given, so
the page and the game's own options change one setting. `Launcher.steam_folders/1` lists
where Steam keeps a game on macOS (CrossOver bottles too), Linux and Windows, for a path
field's `:discover`.

On the page, ↑ and ↓ move, ← and → change a choice, Enter edits a path or presses a button,
and Escape quits.

## Keys

The client's own keys are `Cauldron2D.Drafter.Client.default_keys/0`. The game replaces or
drops any of them with `client_keys/0`.

| Screen | Keys |
| --- | --- |
| Title | `Enter` plays, `s` settings, `h` guide, `q` quits, a page's own key opens it |
| Lobby | `↑`/`↓` (`j`/`k`, `PgUp`/`PgDn`, `Home`/`End`) pick, `Enter` joins, `w` watches, `t` a team, `s` settings, `h` guide, `c` chats, `Esc` back |
| Settings | `↑`/`↓` move over the items, `←`/`→` change the one under the cursor, `Esc` leaves |
| World | The game's bindings, plus the keys below |
| Summary | `Enter` again or on, as the outcome's `:next` says, `Esc` to the lobby |
| Guide | `↑`/`↓`, `PgUp`/`PgDn`, `Home`/`End`, `Esc` or `q` back |

The settings items are the key preset, each action's binding, pointer steering, the
effects and music levels, display, drawing and the frame rate. `Enter` on a binding and then
a key, a mouse button or a notch of the wheel adds it to that binding; `Backspace` removes
the binding's last key, and `Esc` during a rebind cancels it.

In the world:

| Key | Does |
| --- | --- |
| `Esc` | Back: the world to the lobby, the lobby to the title, the title out |
| `q` | Leaves the world for the lobby, and the lobby for the title |
| `^Q` | Backs out a step at a time; `^C` quits from anywhere |
| `?` | Shows the world's key hints, and hides them again; held, shows them until released |
| `t` | Talks: `Enter` sends the line, `Esc` drops it, and no key steers while it is open |
| `Tab` | Opens the settings without leaving the world |
| `=`/`+`, `-`, `0` | Zoom in, out, and back; the wheel zooms too |
| `v` | Cycles the projection the game's `look/0` lists: top-down, oblique, isometric, mode 7, first person |
| `[`, `]` | Turn the view |
| `'`, `;` | Tilt the isometric diamond, or pitch the eye |
| `p` | Pauses the player's own world |

Four actions are unbound until a game binds them through `client_keys/0`: `display` toggles
pictures against block characters, `glyphs` cycles the glyph sets, `menu` opens the game's
own menu, and `mouse_look` lets the pointer turn the eye in first person. Watching, the
arrows and a drag pan the view, the wheel zooms about the pointer, and `0` recentres.

Each connected controller plays one of the client's players — the player, then its seats —
as the settings assign them. `Start` opens the game's menu where it has one; the d-pad and
left stick play the game's directions, and the bumpers turn where a projection turns.

## What draws the world

The surface draws the world in one of two ways: as an image through the terminal's image
protocol, or as coloured glyphs from the same atlas.

Which protocol is used is settled in three steps.

1. A mode forced on the surface, else `CAULDRON_MODE`, else `config :cauldron_2d, mode:`,
   else `:pixel`. The modes are `text`, `pixel`, `kitty`, `iterm2` and `sixel`, and the
   answer is `Cauldron2D.Renderer.resolved/1`.
2. `:text` ends it, and the world is drawn in glyphs. A protocol named outright ends it too.
3. `:pixel` asks the session's own terminal: what it answered the startup probe
   (`Drafter.Terminal.Probe`), or, when it was never asked, what its environment says.
   `:braille` from the environment counts as no protocol. This is
   `Drafter.Widget.Chart.Pixel.terminal/0`.

A terminal that names no protocol is not a failure. `render/2` draws two-cell glyphs in
truecolour from the same cells, and the display row in the settings picks how: pixels where
the terminal has them, braille, or the half, quad, sextant and octant block sets. `glyphs`
forces text. `Cauldron2D.Drafter.Client.Settings.surface_mode/1` is that translation.

The surface reads the same camera view either way, sized from the pane by
`Cauldron2D.Camera.columns_for/1` and `Cauldron2D.Camera.rows_for/1`, so a player switching
between pictures and glyphs keeps their place in the world.

## A picture the game draws itself

A scene with a `:picture` function draws its own frame. On a terminal that keeps images,
`Cauldron2D.Drafter.Client.Picture` decides what size to draw it at and how to send it.
Options are a list or a comma-separated string:

| Option | Does |
| --- | --- |
| `native` | Draws at the game's own size times the largest whole number that fits, and the terminal scales it to the pane |
| `native:N` | Draws at the game's own size times `N` |
| `size:WxH` | Sets the game's own size, over what the game declares |
| `png` | Sends each frame as a PNG, palette when it has at most 256 colours; more CPU, and cheaper over ssh than raw pixels |
| `swap` | Stores each frame before letting the last one go, so the pane never blanks |
| `gpu` | Draws on the graphics card at the pane's size, in the pane |
| `window` | As `gpu`, in a window of its own; the pane stays empty while it is open |
| `software` | Never the graphics card |
| `none` | None of these |

`Picture.parse/1` reads the text and `Picture.default/0` is `[{:native, 2}, :swap]`. A mix
task takes `--picture` and passes it through; `CAULDRON_PICTURE` and
`config :cauldron_2d_drafter, picture:` do the same, and a game sets its own default with
the `:picture` key of its `look/0`.

The cost of a frame grows with its pixel count, so a game whose frames are expensive gives
its look `native:1`. Plain `native` on a large pane can ask for many times the game's own
size. Kitty transmits are zlib-compressed; a terminal whose kitty support is partial takes
`compress: false` on the surface.

A scene that also describes itself for the graphics card with a `:gpu` function is drawn on
the card by default — in the pane when there is one, and as its `:picture` when there is
not. `Cauldron2D.Drafter.Client.Gpu` and `Cauldron2D.Drafter.Client.Stage` run that, with
`cauldron_gpu`.

## Where to go next

| You want to | Read |
| --- | --- |
| Serve the game over ssh or telnet | [Serving over ssh and telnet](serving.html) |
| Put the game in a browser | [`cauldron_2d_net`'s guide](https://hexdocs.pm/cauldron_2d_net/browser.html) |
| Put the game in a desktop window | [`cauldron_2d_wx`'s guide](https://hexdocs.pm/cauldron_2d_wx/window.html) |
| Draw the game | [`cauldron_2d`'s tutorial](https://hexdocs.pm/cauldron_2d/tutorial.html) |
| Write the client module | [Introduction](https://hexdocs.pm/cauldron_core/introduction.html) |
| Sound and music | [Sound and music](https://hexdocs.pm/cauldron_core/sound-and-music.html) |
| Test the client with no terminal | `Cauldron2D.Drafter.Test` |
