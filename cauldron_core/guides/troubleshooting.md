# Troubleshooting

Most Cauldron problems are one of five: the world is not stepping, input is not reaching
it, the view the client draws is empty, sound is silent, or a client module is missing
something. They look alike from the outside, so start by finding which layer is wrong.

## Telling them apart

| What you see | First check | Usually means |
| --- | --- | --- |
| Nothing changes, ever, on any screen | `Cauldron.World.stats/1`: `steps` and `ticks` | The world is not stepping |
| The game moves on its own but ignores the keys | `Cauldron.World.players/1`, then `Cauldron.World.snapshot/1` before and after input | Input is not reaching the game |
| The keys work in one client and not another | The player's keymap and `releases?` | The wrong way of holding keys |
| The game runs, the screen is blank | `view/2` called directly for that player | The view is empty, or no frame is due |
| It should make a sound and does not | `Cauldron.Audio.on?/1` and `Cauldron.Audio.stage/1` | No sink, or no speaker package |
| A front end crashes as it opens | The compiler's warnings for the client module | A missing callback |

`Cauldron.World.game/1` is worth checking first in any of them: it is the module the
world actually runs, and a world started with the wrong one looks like a game that does
nothing.

## A world that never ticks

```elixir
%{players: 1, hz: 50, steps: 0, ticks: 0, behind: 0} = Cauldron.World.stats(world)
```

`steps` counts the game's steps and `ticks` the ticks that ran one. Both at zero, with a
player joined, has three common causes.

**It was started with `tick: :on_input`.** Such a world has no clock; it steps once
each time a player's input arrives. A turn-based game is meant to sit still. Send input
and look again: `steps` moves by one per input.

**The `:tick` option is not one of the two words.** Only `:fixed` and `:on_input` are
recognised. `tick: :oninput`, `tick: false` or a string is neither: no clock is started
and no input steps the game. The default is `:fixed`; leave the option out if in doubt.

**It is paused.** `Cauldron.World.paused?/1` says. `pause/1` stops a clocked world
stepping until `resume/1`, and time paused is not owed afterwards. A world that steps on
input keeps stepping; `pause/1` does not hold it.

A world that is not stepping because its process is gone does not answer at all: the
call exits. A world started with `start_link/1` from a process that exits stops with it.
`stats/1` answering is itself the proof the world is alive.

## Input that never arrives

Input is a cast to the world and returns `:ok` before the world sees it, and the world
drops it silently when the id is not one of its players. So the first question is
whether the player is present:

```elixir
Cauldron.World.players(world)
#=> [:alice]
```

If the id is not in the list, the join failed or was made somewhere else. `Cauldron.Player.join/4`
answers `{:error, :taken}` when another process already plays that id, and the game's own
`{:error, reason}` when the game refused. Input sent before a successful join is
dropped.

If the player is present, the next question is whether the game saw anything. Watch the
state across a step:

```elixir
before = Cauldron.World.snapshot(world)
:ok = Cauldron.Player.input(world, :alice, %{held: MapSet.new([:right]), aim: nil})
Process.sleep(100)
after_input = Cauldron.World.snapshot(world)
```

A state that never changes means the input did not reach the game: the id was not a
player, or a `handle_input/3` clause whose pattern did not match the input map raised and
took the world with it. A game that accepts input but does not keep it looks different:
`handle_input/3` changes the state once, and `step/2` has nothing to act on after that.

On the client side the same symptom has a different cause: the input instance holds
nothing. Check, in order:

* the key is in the keymap for the action, spelled as `Cauldron.Input.spec_of/1` gives it;
* `releases?` matches the terminal — a terminal that reports releases needs
  `releases?: true`, and one that does not needs `releases?: false` (the default) and a
  `:tap_ms` that outlasts the gap between frames;
* `Cauldron.Input.expire/2` is called once a tick with the same millisecond clock the
  events use — mixing seconds with milliseconds makes every hold expire at once, or never;
* `:holds` is set for actions on a terminal that waits before repeating, or a long hold
  becomes a tap that ends before the next frame;
* `:tap_ms` is shorter than the time between two frames, so a quick tap expires before
  any input is sent.

For a turn-based world, a press that begins and ends between two steps still counts for
one step: the world unions the held actions of every input since the last step
(`Cauldron.World.Pending`). That is not a reason for input to disappear.

`frames: false` on a join is not an input problem: input still arrives, but the player is
sent no frames, so a client would look stuck.

## A view that is empty

First separate the game from the client. The game's `view/2` is pure, so call it:

```elixir
snapshot = Cauldron.World.snapshot(world)
Tag.Game.view(snapshot, :alice)
```

In a test, `Cauldron.Test.view/2` does the same on the driver. If the view is `nil` or a
map with nothing in it, the game is the problem: the client can only draw what it is
sent.

If `view/2` returns something, ask whether a frame is due. `view/2` is called only for a
player a frame is due to, and a player joined with `frames: false` never gets one. A
client shows nothing at all before a world's first frame; that is what `opening/1` is
for.

A third case is a scene that is not empty but has nothing visible in it. The view is the
game's data; the scene is what the client draws from it, built by the game's `scene/1`
or `scene/2`. A scene missing the keys its drawing package reads — for a 2D game, the
focus, the bounds and the movers — is a drawing problem, not a world one: the view
arrived and was turned into an empty picture. Compare the view the frame carried with
the scene the client's client module builds from it.

## Sound that is silent

The most common cause is a missing package, not a missing sound. `cauldron_core` plays
through `tuning_fork`, and only `tuning_fork_speaker` can open this machine's speaker.
Without it the stage stays silent and the sound calls are no-ops that return `:ok`:

```elixir
Cauldron.Audio.start(sounds: &Tag.Sound.voice/1)
#=> false

Cauldron.Audio.on?(Cauldron.Audio)
#=> false

Cauldron.Audio.stage(Cauldron.Audio)
#=> nil
```

Add `tuning_fork_speaker` to the deps and recompile; it builds C, so a missing compiler
or, on Linux, missing ALSA headers (`libasound2-dev`) is the next thing to look at. On a
server with no sound card the same silence is by design.

When `on?/1` is true, check what is being asked to play:

* the sink: `Cauldron.Audio.Sink.silent/0` is silent on purpose, and a player's `sink/1`
  may be a process or a socket;
* the levels: `Cauldron.Audio.levels/3` or a settings screen may have set effects or music
  to zero, and `Cauldron.Audio.mute/2` silences both;
* the table: `sounds/0` returning `nil` for the event, or a function with no clause for it,
  plays nothing — the audio instance rescues a `FunctionClauseError` and treats the event
  as silent;
* the placement: a placed event is silent at `:earshot` tiles or further from the listener,
  and a listener of `nil` is only the absence of distance, not of sound;
* the voice: a voice with a zero gain, or an envelope of zero length, is effectively
  silent even though it plays.

`Cauldron.Audio.playing/1` says which bed was last asked for, and
`Cauldron.Audio.Music.current/1` which piece and section are playing. A rendered piece
that fails to render is logged and never plays; a bed asked for before its render
finishes plays when the render arrives, so a first play can lag by the length of a
render.

## A client module missing a callback

The behaviour's required callbacks are `title/0`, `view/0`, `actions/0`, `keymaps/0`,
`toggles/0`, `worlds/1`, `scene/1`, `hud/1`, `listener/1`, `sounds/0`, `music/0` and
`cue/2`. `use Cauldron.Client.Game` defines the ones most games write the same way —
`toggles/0`, `hud/1`, `listener/1`, `sounds/0`, `music/0`, `cue/2` and `scene/1` — so a
module that uses it still has to write `title/0`, `view/0`, `actions/0`, `keymaps/0`,
`worlds/1` and `scene/2`.

That last one is the quiet one. The generated `scene/1` calls your `scene/2`. A module
that defines neither compiles cleanly — `use` has already provided `scene/1` — and the
first frame raises `UndefinedFunctionError` for `scene/2`. Write `scene/2`, or write
`scene/1` and override it.

The compiler names the rest:

```
warning: function title/0 required by behaviour Cauldron.Client.Game is not implemented
```

Warnings appear when the module is compiled, so a module carried over from an old build
can fail only at runtime. `mix compile --warnings-as-errors` turns them into build
failures, and `@impl true` on a function that is not a callback is a warning too: the
attribute says the function implements the behaviour, and nothing does.

Every other callback is optional, and a front end asks for it through
`Cauldron.Client.Game.optional/4`, so a game with no `fronts/1` gets the client's own
title, and one with no `pages/1` gets no extra title pages. That is a choice, not a bug.

## Where to go next

| You want to | Read |
| --- | --- |
| Check a world's tick and input by hand | [Worlds and players](worlds-and-players.html) |
| Check what the client reads from the keyboard | [Input and menus](input-and-menus.html) |
| Check the sound path end to end | [Sound and music](sound-and-music.html) |
| Drive the game without a world to compare | [Testing](testing.html) |
| Find a word | [Glossary](glossary.html) |
