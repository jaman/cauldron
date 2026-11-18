# Extending the engine

This chapter is for someone adding to the engine: a new world or client behaviour
implementation, a new way of drawing, a new front end, or a new package in the family.
It names the behaviour or protocol to implement and the callbacks it asks for. Every
name here is the one in the source.

## A world module

Implement `Cauldron.Game`. It is the whole of a game's state and rules.

| Callback | Called when | Returns |
| --- | --- | --- |
| `init/1` | the world starts, with the world's options | the state |
| `join/3` | a player joins | `{:ok, state}` or `{:error, reason}` |
| `leave/2` | a player leaves | the state |
| `handle_input/3` | a player's actions change | the state |
| `step/2` | each tick, with the seconds since the last | the state |
| `view/2` | a view is needed for a player | anything the client module's `scene/2` accepts |
| `drain_events/1` | after stepping | `{events, state}` |

`export/1`, `restore/1`, `checksum/1` and `input_delay/1` are optional; a world that is
replayed across machines implements the first three.

```elixir
defmodule MyGame.World do
  @behaviour Cauldron.Game

  @impl true
  def init(_opts), do: %{score: 0, coin: {5, 5}}

  @impl true
  def join(state, _player, _props), do: {:ok, state}

  @impl true
  def leave(state, _player), do: state

  @impl true
  def handle_input(state, _player, _actions), do: state

  @impl true
  def step(state, _seconds), do: state

  @impl true
  def view(state, _player), do: state

  @impl true
  def drain_events(_state), do: {[], %{}}
end
```

The module is never started as a process. `Cauldron.World` is the process and calls the
module; that is what lets `Cauldron.Test` run a game with no clock and no mailbox.

## A client module

Implement `Cauldron.Client.Game` — the module every front end is given.

`use Cauldron.Client.Game` fills in the parts that have a sensible default: `toggles/0`,
`hud/1`, `listener/1`, `sounds/0`, `music/0`, `cue/2` and a `scene/1` that calls
`scene/2`. What remains yours is the part that describes the game:

| Callback | Describes |
| --- | --- |
| `title/0` | the name and tagline |
| `view/0` | the module implementing `Cauldron.Client.View` |
| `actions/0` | the actions a player can press |
| `keymaps/0` | key to action, per screen |
| `worlds/1` | the worlds a player can join |
| `scene/2` | a view as the scene a front end draws |
| `hud/1` | the hud rows |

`scene/2` is optional when the default is enough; `fronts/1`, `holds/0`, `steering/0`,
`padmap/1`, `local_seats/1` and `outcome/1` change how the screens behave, and are
optional too.

## A view

`Cauldron.Client.View` is how a kind of game is drawn and looked at. `cauldron_2d`
implements it as `Cauldron2D.Client.View`; a package with a different idea of a picture —
a 3D one, say — implements the same callbacks.

| Callback | Answers |
| --- | --- |
| `look/1`, `cycle/1`, `turn/2`, `tilt/2`, `dragged/2` | the player's look, and how input changes it |
| `zoom/1`, `zoom_levels/2` | how far in the look is, and the sizes it can step through |
| `props/4` | the drawing props for a scene at a look and zoom |
| `steered/2` | a player's input turned by the look |
| `world_direction/2` | which way a direction points in the world |
| `turns_with_pointer?/1`, `stick_turns?/1` | whether the pointer or a stick steers |

A client module names its view with `view/0`. `Cauldron.Client.Stage`, `Party` and
`Controls` call the view rather than a 2D or 3D module, which is why core has no
dependency on either.

## A drawer

`Cauldron.Net.Drawer` is what a front end implements to put its frames on the wire. The
session opens a drawer per client, tells it the pane size, and asks it for the pushes
that show each scene.

| Callback | Called to |
| --- | --- |
| `open/2` | start from a game module and the socket's options |
| `changed/3` | notice a message the drawer cares about (an atlas change) |
| `pane/2` | record the client's pane size |
| `draw/2` | turn drawing props into pushes |
| `world_at/3` | turn a click at a fraction of the pane into a world position |
| `close/2` | stop |
| `colour/1` | resolve a hud's named colour |
| `local/2` | turn a push into an owner message, for a link in the same VM |
| `reader/1`, `read/4` | read a socket link's messages |
| `remote/2`, `browser/0` | a remote view and the scripts the page loads |

`Cauldron2D.Net.Drawer` is the 2D implementation and the one to read first.

## A renderer

`Cauldron3D.Scene.Target` is a protocol. A renderer implements it, and every converter
uploads through it:

```elixir
defprotocol Cauldron3D.Scene.Target do
  def submit(target, changes)
  def mesh(target, mesh)
  def texture(target, texture)
  def canvas(target, canvas)
  def material(target, material)
  def scatter(target, scatter)
  def release(target, handle)
  def capabilities(target)
end
```

`submit/2` takes a tick of `Cauldron3D.Scene.Stream` changes; `mesh/2`, `texture/2`,
`canvas/2`, `material/2` and `scatter/2` upload an object and return its
`Cauldron3D.Scene.Handle`; `release/2` frees one; `capabilities/1` says what the
renderer can draw. A renderer that cannot draw something should
say so rather than silently drop it — `Cauldron3D.Scene.Software` lists exactly what it
does not draw.

## A front end

A new front end is a package that:

1. Implements a drawer for the protocol its frames use.
2. Runs the screens with `Cauldron.Front`, handing it the client module.
3. Maps its input events to `Cauldron.Input` actions.
4. Declares `Cauldron.Client.Game` as its dependency, never the other way round.

`cauldron_2d_wx` is the smallest complete example: one `run/1` that starts wx, one view
module and one key mapping.

## Adding a package or a guide

A package in the family:

- is its own Mix project with `@version`, `description`, `package/0`, `docs/0`,
  `@source_url` and an `ex_doc` dev dependency;
- takes sibling dependencies through `family/4` in its `mix.exs`, so the path is used in
  the repository and the Hex requirement outside it;
- sets `elixirc_options: [warnings_as_errors: true]`;
- ships `LICENSE` and `COMMERCIAL.md`;
- documents every public module.

A guide is a markdown file under the package's `guides/`, listed in `docs/0`'s `extras`
and in a `groups_for_extras` group. Package guides are written for someone *using* the
package. They say how to use it, not how it was built: no release notes, no
"this changed because", no account of a bug that was fixed on the way. History belongs
in `CHANGELOG.md`, and design reasoning belongs in the book's developer chapters.
