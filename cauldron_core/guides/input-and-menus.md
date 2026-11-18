# Input and menus

Input reaches a game as a set of actions the player is holding. A game declares its
actions and the keys that press them; a client reads the terminal's events, the mouse and
the game controllers into that set. `Cauldron.Input` does the reading, `Cauldron.Presses`
turns it into presses and releases, and `Cauldron.Menu` gives the front ends' menus their
behaviour.

## Actions and keymaps

An action is an atom the game invents: `:left`, `:jump`, `:fire`. A keymap maps each
action to the keys that hold it:

```elixir
keymap = %{
  left: [:left, :a],
  right: [:right, :d],
  jump: [:up, {:w, []}, :left_shift],
  fire: [{:mouse, :left}]
}

input = Cauldron.Input.new(keymap, releases?: true, toggles: [:jump])
```

A key spec is a key name, `{:f, [:ctrl]}` for a key that needs modifiers, or
`{:mouse, button}` for a mouse button. Keys are matched by their unshifted name: `:A` and
`{:a, [:shift]}` both press what `:a` is bound to. A binding with modifiers matches only
with them; a bare key matches with any.

A game gives its client module the actions and keymaps in `actions/0` and `keymaps/0`.
The client keeps the player's keymap in their settings as `:bindings` and saves it with
the rest, so a binding changed in a menu is the binding used next time.

## Reading events

Feed every event to `handle/3` with a millisecond reading, and call `expire/2` once a
tick:

```elixir
now = System.monotonic_time(:millisecond)

input =
  input
  |> Cauldron.Input.handle({:key_down, :a, []}, now)
  |> Cauldron.Input.handle({:key_up, :a, []}, now + 200)
  |> Cauldron.Input.expire(now + 200)

Cauldron.Input.state(input)
#=> %{held: MapSet.new(), aim: nil}
```

`state/1` is what the game receives as `handle_input/3`'s input:
`%{held: actions, aim: {x, y} | nil}`, with `:strength` for actions an analog control
holds only partly and `:drag` while a mouse drag is under way. A mouse event's pointer
position becomes the aim, and a drag adds the pointer's travel to `:drag`.

## Two ways to hold a key

A terminal may report key releases or not. Which one a client has decides how
`Cauldron.Input` reads the events, and a game must not assume one:

| `releases?: true` | `releases?: false` |
| --- | --- |
| An action is held from `{:key_down, key, mods}` to `{:key_up, key, mods}` | A `{:key, key}` press holds for `:tap_ms`, extended by each repeat |
| Legacy `{:key, ...}` events are ignored | `{:key_release_support, true}` switches to the first way and drops every hold |
| Long holds need nothing | `:holds` gives an action a longer first window, to cover the terminal's repeat delay |
| — | `:toggles` flips an action on each press and keeps it until pressed again |

A game tells a client which actions need `:holds` in `holds/0`, with the milliseconds
each is held. The client passes `:steering` from `steering/0`, the actions a key press
takes back from the pointer. `Cauldron.Input.new/2` takes `:tap_ms` (default 120),
`:repeat_ms` (default 150), `:holds`, `:toggles`, `:steering` and `:gesture_ms` (default
100, for wheel notches and pointer movement).

The wheel and the pointer's movement are bound like keys that are tapped:
`{:mouse, :wheel_up}`, `{:mouse, :wheel_down}`, and `{:mouse, :move_left}` and the other
three directions. Their holds are kept apart from the keys', so letting go of a key never
drops what the mouse holds.

`Cauldron.Input.merge/3` adds the actions another source holds, with how hard each is
held:

```elixir
input =
  Cauldron.Input.merge(
    input,
    Cauldron.Input.Pad.held(pad),
    Cauldron.Input.Pad.strength(pad)
  )
```

## Presses and releases

A game that cares about the moment a key went down, not just that it is down, keeps a
`Cauldron.Presses` in its state with each player. It is a plain value; no process:

```elixir
defmodule Tag.Game do
  def init(_opts), do: %{players: %{}}

  def join(state, id, _props) do
    player = %{
      grounded?: true,
      vy: 0.0,
      held: MapSet.new(),
      presses: Cauldron.Presses.new()
    }

    {:ok, put_in(state.players[id], player)}
  end

  def handle_input(state, id, %{held: held}) do
    player = Map.fetch!(state.players, id)

    player =
      if :jump in Cauldron.Presses.pressed(player.presses, held) and player.grounded?,
        do: %{player | vy: 3.0},
        else: player

    put_in(state.players[id], %{player | held: held})
  end

  def step(state, dt) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, %{player | presses: Cauldron.Presses.settle(player.presses, player.held, dt)}}
      end)

    %{state | players: players}
  end
end
```

`pressed/2` is what was taken up since the last step, `released/2` what was let go.
`settle/3` is called once a step, after the game has acted, and remembers what was held.
`buffered?/4` is whether an action was pressed within a window of seconds, this step or a
recent one — a jump pressed just before landing. A game that acts on a buffered press
calls `clear/2`, so one press does one thing. Presses older than a second are forgotten.

## Controllers

A controller is read into the same actions. A padmap maps actions to buttons and axes in
the Xbox layout, whatever the hardware:

```elixir
padmap = %{left: [:dpad_left, {:axis, :left_x, :neg}], jump: [:a, :right_bumper]}
pad = Cauldron.Input.Pad.new(padmap, deadzone: 0.3)
```

Feed each controller event map — the `%{type: :button | :axis | :disconnected, ...}` a
client receives as `{:controller, event}` — to `Cauldron.Input.Pad.handle/2`; `held/1` is
the set of actions held and `strength/1` how hard each axis-driven one is pushed. A stick
may aim instead of holding actions: give the padmap an `:aim` entry of
`[{:stick, :left}]` or `[{:stick, :right}]` and `Cauldron.Input.Pad.aim/1` gives the
direction it is pushed in, or `nil` inside the deadzone.

A client derives a default padmap from the game's `actions/0` and first keymap through
`Cauldron.Client.Game.padmap/3`, which uses `Cauldron.Input.Pad.default_map/3`; a game
that wants its own writes `padmap/1`, given the client's props.

On one machine there may be more than one player. A game names their keys in
`local_seats/1`: a keymap for each further seat. The client joins each as
`"<username> 2"` with `frames: false`, and every key reaches every seat and counts where
that seat's keymap binds it. `Cauldron.Client.Controllers` decides which controller plays
which player; `Cauldron.Client.Party` holds the player, the seats and that routing
together.

## Menus

`Cauldron.Menu` is how a game's menu behaves: pages of rows, a cursor on each,
going into a page and back, changing settings, waiting for a key to bind, taking typed
text and asking yes or no. It knows nothing about how the menu looks.

A page maps a name to a title and its items. `Cauldron.Menu.Item` builds the rows:

| Item | Behaves as |
| --- | --- |
| `Item.action/2` | Does a result when chosen: `:close`, `:leave`, `:back`, `:stay`, `{:page, name}`, `{:request, term}`, `{:confirm, text, result}` |
| `Item.page/2` | Opens a page, coming back on `:back` |
| `Item.toggle/3` | Turns the boolean at a path on and off |
| `Item.choice/4` | Steps through `{value, text}` pairs |
| `Item.slider/4` | Moves a number within a range |
| `Item.binding/2` | Shows the keys bound to an action; choosing it waits for a key |
| `Item.text/3` | Takes typed characters |
| `Item.gap/0`, `Item.note/1` | The cursor passes over them |

A path is a list of keys into the player's settings: `[:music]` is the music level,
`[:options, :flashing]` one of the game's own options.

```elixir
defmodule Tag.Menus do
  alias Cauldron.Menu.Item

  def pages do
    %{
      main: %{
        title: "TAG",
        items: [
          Item.action("PLAY", {:request, :play}),
          Item.toggle("FLASHING", [:options, :flashing]),
          Item.slider("MUSIC", [:music], 0.0..1.0, step: 0.1),
          Item.action("QUIT", {:confirm, "LEAVE THE GAME?", :leave})
        ]
      }
    }
  end
end
```

Wire it into the client module exactly as `Cauldron.Client.Game` asks:

```elixir
def open_menu(settings), do: Cauldron.Menu.open(Tag.Menus.pages(), settings)

def menu_event(menu, event, settings), do: Cauldron.Menu.event(menu, event, settings)
```

`Cauldron.Menu.event/3` returns `%{menu: menu_or_nil, settings: settings}`, with
`:sounds` when the menu makes any, `:request` when an action sends the world something,
and `leave: true` when one leaves the world. That is what `menu_event/3` must return. A
`nil` menu closes it; changed settings are saved and take effect at once.

An event becomes `:up`, `:down`, `:left`, `:right`, `:choose` or `:back` by its key
against `:keys`, then by the game action the player's bindings give that key against
`:actions`. While a binding waits, the next key, mouse button or wheel notch becomes the
action's only key, and `Esc` gives up. While typing, a printable key adds its character,
`Backspace` takes one off, `Enter` keeps the text and `Esc` gives up. A prompt takes
`:choose` (or `y`) as yes and `:back` (or `n`) as no.

Draw it from the rows the menu gives:

```elixir
def scene(_view, %{menu: menu}) when not is_nil(menu) do
  %{
    title: Cauldron.Menu.title(menu),
    rows: Cauldron.Menu.rows(menu),
    prompt: Cauldron.Menu.prompt(menu),
    menu: menu
  }
end
```

`Cauldron.Menu.rows/1` gives each row's `:index`, `:item`, `:kind`, `:label`, `:value`,
`:fraction`, `:focused?` and `:waiting?`. `Cauldron.Menu.window/2` keeps the cursor in
view when only so many rows fit, and `Cauldron.Menu.prompt/1` is what the menu is waiting
for, if anything. `Cauldron.Menu.pad?/1` says whether the last key came from a
controller.

The menu's own keys can be changed with `:keys` (over the defaults: arrows, wheel,
`Enter`, space, `Esc`), the game's buttons can be mapped with `:actions`, and menu
sounds with `:sounds` from the game's `sounds/0` table.

## What the client owns

Not every key is the game's. A client has its own: back, settings, zoom, projection, the
game's menu, chat, the guide. `Cauldron.Client.Keys` holds their defaults, and a game
overrides them in `client_keys/0`; `Cauldron.Client.Keys.of/1` merges the two. A key
bound to `nil` is unbound. The client's menu key is unbound by default — a game that has
a menu binds `menu` there or opens it from a front of its own.

## Where to go next

| You want to | Read |
| --- | --- |
| Understand what receives the action | [Worlds and players](worlds-and-players.html) |
| Give the game a menu page of its own | [Saving and scores](saving-and-scores.html) |
| Play sound when a menu moves | [Sound and music](sound-and-music.html) |
| Find a word | [Glossary](glossary.html) |
