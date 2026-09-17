# Your first game: Cistern

This guide builds a small game from nothing and puts it in a terminal, in a browser and
in a window, with sound, a second player and a computer opponent along the way. Every
piece of it is in [`examples/cistern`](https://github.com/jaman/cauldron/tree/main/examples/cistern)
in the repository, tests included, so you can read the finished thing beside each step.

The game: **drops fall from the top of a small field; you hold a bucket on the bottom
row and catch them.** A gold drop is worth three. Miss three and the cistern overflows.

By the end you will have used:

| step | what you use |
|---|---|
| the game as a value | `Cauldron2D.Game`, `Cauldron2D.Rng`, `Cauldron2D.Tuning` |
| testing it | `Cauldron2D.Test` |
| the art | `.pic` files, `atlas.txt`, `Cauldron2D.Atlas`, a derived picture |
| on screen | `Cauldron2D.Client.Game`, `Cauldron2D.Drafter.Client` |
| sound | `Cauldron2D.Audio`, `Cauldron2D.Audio.Music` |
| more players | `Cauldron2D.Arenas`, `Cauldron2D.Robot`, `Cauldron2D.World` |
| a browser | `Cauldron2D.Net.Socket`, `Cauldron2D.Net.Channel`, `Cauldron2D.Net.Pages` |
| a window | `Cauldron2D.Wx.Client` |
| replays and numbers | `Cauldron2D.Replay`, `Cauldron2D.Tuning`, `mix cauldron.report` |

## 0. A project

```
mix new cistern
```

Add the engine, the terminal front end and the art loader; the browser and the window
come later:

```elixir
defp deps do
  [
    {:cauldron_2d, "~> 0.1"},
    {:cauldron_2d_drafter, "~> 0.1"},
    {:linocut, "~> 0.1"},
    {:tuning_fork_speaker, "~> 0.1"}
  ]
end
```

`tuning_fork_speaker` is what makes sound come out of this machine; without it the game
runs silent.

## 1. The game as a value

A Cauldron game is a value and a handful of pure functions over it. Nothing in it reads a
clock, draws or plays a sound. The engine calls these functions; the game answers.

```elixir
defmodule Cistern.Game do
  @behaviour Cauldron2D.Game
  ...
end
```

The behaviour is seven callbacks:

- `init/1` builds the starting state from options.
- `join/3` seats a player; `leave/2` removes one.
- `handle_input/3` is told what a player is holding — a set of actions, and where they
  point.
- `step/2` moves the world by `dt` seconds.
- `view/2` is what one player sees.
- `drain_events/1` is what happened since it was last asked.

### The state

```elixir
defstruct buckets: %{}, drops: [], rng: nil, tuning: nil, until_next: 0.0, events: []
```

A bucket per player, keyed by their id; the drops in the air; a random number generator;
the numbers the game plays by; a timer to the next drop; the events waiting to be
drained.

### Starting

```elixir
@impl true
def init(opts) do
  {rng, _seed} =
    case Keyword.get(opts, :seed) do
      nil -> Rng.random()
      seed -> {Rng.new(seed), seed}
    end

  tuning = Settings.new(Keyword.get(opts, :tuning, []))
  %__MODULE__{rng: rng, tuning: tuning, until_next: Tuning.get(tuning, :spawn_every)}
end
```

Two things to notice. The random generator lives *in the state*: `Cauldron2D.Rng` gives
you `{value, next_rng}` and you keep the next one. That is what makes a game with the
same seed play the same rain every time — which is what makes replays and tests
possible.

The numbers live in a `Cauldron2D.Tuning`. `Cistern.Tuning` declares them once, with
defaults, limits and a line of documentation each:

```elixir
@spec_list [
  fall: [default: 3.0, limits: {1.0, 12.0}, doc: "tiles a second a drop falls"],
  spawn_every: [default: 1.2, limits: {0.3, 4.0}, doc: "seconds between drops"]
]

def new(overrides \\ []), do: Tuning.new(@spec_list, overrides)
```

Later a settings screen can show and change them; `Tuning.put/3` keeps a value inside its
limits.

### Players

```elixir
@impl true
def join(%__MODULE__{} = game, id, props) do
  bucket = %{id: id, name: Map.get(props, :username, "player"), x: @width / 2 - 1,
             score: 0, misses: 0, held: MapSet.new(), aim: nil}
  {:ok, %{game | buckets: Map.put(game.buckets, id, bucket)}}
end

@impl true
def leave(%__MODULE__{} = game, id), do: %{game | buckets: Map.delete(game.buckets, id)}
```

`props` are whatever the front end passes at the join; every Cauldron client passes
`:username`. A game that wants teams or a character choice names its own props and reads
them here.

### Input

```elixir
@impl true
def handle_input(%__MODULE__{} = game, id, %{held: held} = input) do
  case Map.fetch(game.buckets, id) do
    {:ok, bucket} ->
      %{game | buckets: Map.put(game.buckets, id, %{bucket | held: held, aim: Map.get(input, :aim)})}

    :error ->
      game
  end
end
```

Input is not keys. It is a `MapSet` of the **actions** the player is holding — `:left`,
`:right` — and an `aim`, the tile the pointer is over, if the front end has one. Which key
means which action is settled elsewhere (step 4), and the same game reads a keyboard, a
mouse and a browser touch the same way. `handle_input/3` is called only when a player's
input changed; `step/2` sees what they hold every tick.

### Stepping

```elixir
@impl true
def step(%__MODULE__{} = game, dt) do
  game
  |> steer(dt)
  |> spawn_drop(dt)
  |> fall(dt)
end
```

`steer/2` moves each bucket by what it holds — towards the pointer if there is an aim,
else `@speed * dt` in the direction of the key. `spawn_drop/2` counts down and puts a new
drop at a random column, gold one time in six:

```elixir
defp spawn_drop(game, _dt) do
  {column, rng} = Rng.roll(game.rng, @width)
  {gold?, rng} = Rng.chance(rng, 1, 6)
  drop = %{x: column - 1, y: 0.0, kind: if(gold?, do: :drop_gold, else: :drop)}
  %{game | rng: rng, drops: [drop | game.drops], until_next: Tuning.get(game.tuning, :spawn_every)}
end
```

`fall/2` moves every drop down by `fall * dt` and lands the ones that reach the bottom
row: a bucket underneath catches it, otherwise it is a miss for everyone still playing.

`dt` is whatever the world passes — `1 / hz` — and nothing here assumes what it is. Run at
30 or 60 ticks a second, the drops fall at the same speed.

### What happened

```elixir
defp catch_drop(game, bucket, drop) do
  worth = if drop.kind == :drop_gold, do: 3, else: 1
  caught = %{bucket | score: bucket.score + worth}

  %{game | buckets: Map.put(game.buckets, bucket.id, caught)}
  |> emit({:catch, drop.kind, {drop.x, @bottom}})
end

@impl true
def drain_events(%__MODULE__{events: events} = game),
  do: {Enum.reverse(events), %{game | events: []}}
```

Events are the game's own terms — `{:catch, kind, pos}`, `{:splash, pos}`, `{:out, id}`.
The engine attaches no meaning to them. They go to every player each tick, and in step 5
they become sounds; a position in an event is where the sound comes from.

### What a player sees

```elixir
@impl true
def view(%__MODULE__{} = game, id) do
  %{me: Map.get(game.buckets, id), buckets: Map.values(game.buckets), drops: game.drops,
    size: size(), misses_allowed: @misses_allowed}
end
```

A view is any term. It is sent to that player every tick, and everything a front end
draws — the scene, the hud, the summary at the end — is read from it. A game with fog of
war sends each player only what they can see, because `view/2` is asked per player.

`outcome/1` reads the view and says when it is over for this player:

```elixir
def outcome(%{me: me, misses_allowed: allowed} = view) when me.misses >= allowed do
  %{title: "The cistern overflows", lines: ["#{me.score} caught", ...], next: :same_arena}
end

def outcome(_view), do: nil
```

`next: :same_arena` means the summary screen's *again* starts the same arena over.

## 2. Testing it without a world

`Cauldron2D.Test` drives a game the way a world would — join, hold, tick — with no
process and no clock:

```elixir
alias Cauldron2D.Test, as: World

{:ok, driver} =
  Cistern.Game
  |> World.new(game_opts: [seed: 1], hz: 30)
  |> World.join(:alice, %{username: "alice"})

walked = driver |> World.hold(:alice, [:right]) |> World.tick(15)
assert World.view(walked, :alice).me.x > start
```

`hold/4` takes the actions and an aim; `tick/2` runs steps; `until/3` ticks until a
condition holds; `events/1` is everything drained so far. The tests in
`test/cistern/game_test.exs` cover steering by key and by pointer, a catch, three misses
and the summary, and that the same seed makes the same rain.

## 3. The art

Every tile a Cauldron game draws lives in a `Cauldron2D.Atlas`: a name, a picture, a
glyph and a colour for terminals without pictures, and a rate if it is animated. The
simplest way to make one is a directory of `.pic` files.

A `.pic` is a palette, a blank line, and the picture, one character a pixel, `.`
transparent:

```
B #c8a060
R #8a6a3a
H #ffe0a0

................
................
................
................
................
................
................
HHHHHHHHHHHHHHHH
BBBBBBBBBBBBBBBB
.BBBBBBBBBBBBBB.
.BBBBBBBBBBBBBB.
..BBBBBBBBBBBB..
..BBBBBBBBBBBB..
...RRRRRRRRRR...
...RRRRRRRRRR...
................
```

That is `priv/art/bucket.pic`. `drop.pic` has two frames separated by a `---` line, so
it animates. Beside them, `atlas.txt` gives each art its glyph and colour for a text
terminal, its frame rate, and — for `drop_gold` — a derivation:

```
bucket	u 	#c8a060
drop	o 	#6cb8ff	6
drop_gold	o 	#ffd040	6	from drop; colour W #ffd040; colour L #fff0b0
floor	==	#4c527a
sky	  	#14162a
```

`drop_gold` is never drawn. It is the drop with two palette entries changed, rebuilt
from `drop.pic` every time the atlas loads; edit the drop and the gold drop follows.
`Linocut.Derive` lists the operations: recolour a key, flip, turn, shift, pick a frame,
lay one picture over another.

Loading it is one call:

```elixir
def install do
  if Atlas.installed?(@name) do
    @name
  else
    {:ok, atlas} = Atlas.load(@name, dir(), tile: @tile, void: {10, 11, 20})
    Atlas.install(atlas)
  end
end
```

An installed atlas is shared by every process on the node under its name, and a game
that `Atlas.subscribe/1`s to it is told when it changes — which is what the editors do
on save, so you can redraw a tile while the game runs.

You do not have to write pictures by hand. `cauldron_2d_easel_drafter` is an editor in
the terminal (`mix cauldron.easel priv/art --tile 16 --atlas cistern`),
`cauldron_2d_easel_web` the same in a browser, `cauldron_2d_easel_kino` in Livebook.
Or draw in code: `Linocut.sprite/3` turns a picture string into a raster, and
`FrenchCurve.Draw` has lines, rectangles and circles — Carom's bricks and Scriber's
walls are drawn that way.

## 4. On screen

The game does not know it is being drawn. What a front end needs is a second module,
`Cauldron2D.Client.Game`, that says how to show the game: its title, its atlas, its
actions and keys, its arenas, and how a view becomes a scene and a hud.

```elixir
defmodule Cistern.Client do
  @behaviour Cauldron2D.Client.Game

  def title, do: %{name: "CISTERN", tagline: "catch the rain"}
  def atlas, do: Cistern.Art.install()
  def actions, do: [:left, :right]

  def keymaps do
    [
      arrows: %{left: [:left, :a], right: [:right, :d]},
      vi: %{left: [:h], right: [:l]}
    ]
  end

  def toggles, do: []
  def steering, do: [:left, :right]
  ...
end
```

`keymaps/0` are presets the player picks between in the settings screen, and can rebind
key by key. `steering/0` names the actions the pointer also drives: with pointer steering
on, the bucket follows the mouse, and pressing a steering key takes over until the mouse
moves again.

### The scene

```elixir
def scene(view) do
  {width, height} = view.size
  floor = height - 1

  %{
    focus: {width / 2, height / 2},
    bounds: view.size,
    cell: fn {_x, y} -> if(y == floor, do: {:floor, [], nil}, else: {:sky, [], nil}) end,
    movers:
      Enum.map(view.buckets, &{:bucket, {&1.x, floor - 1.0}}) ++
        Enum.map(view.buckets, &{:bucket, {&1.x + 1, floor - 1.0}}) ++
        Enum.map(view.drops, &{&1.kind, {&1.x / 1, &1.y}}),
    labels: Enum.map(view.buckets, &{&1.name, {&1.x, floor - 2.0}, {255, 240, 200}})
  }
end
```

A scene is a camera focus, the world's bounds, and two kinds of thing to draw:

- **cells** — `cell.({x, y})` answers what is on the grid at a tile: an art, a list of
  arts laid over it, and a tint. The engine asks only for the tiles on screen.
- **movers** — arts at fractional positions, for anything that moves between tiles: the
  buckets and the drops.

A label is text drawn over the world at a tile position. That is the entire drawing
interface; the engine composes the frame, and each front end sends it the way its
display takes it.

### The hud

```elixir
def hud(%{me: me} = view) do
  [
    {:score, [{"caught #{me.score}", {255, 224, 120}}]},
    {:misses, [{"missed #{String.duplicate("x ", me.misses)}", {235, 110, 130}}]},
    {:drops, [{"#{length(view.drops)} in the air", nil}]}
  ]
end
```

Rows of runs, each run text with a colour. A tag on a row lets a front end style it;
otherwise it is data every front end draws the same way. `Cauldron2D.Client.Hud`
describes the shapes, including a column beside the world.

### Running it

The terminal front end is a ready-made application:

```elixir
Drafter.run(Cauldron2D.Drafter.Client, props: %{game: Cistern.Client})
```

`mix cistern` in the example does this after registering the surface widget:

```elixir
Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
```

You get a title, a settings screen (key presets and rebinding, pointer steering, sound
levels, pixels or glyphs, frame rate), the arena with your hud, a summary when
`outcome/1` says so, and a guide from `guide/0` — all from the client module. Where the
terminal draws pictures (kitty, iTerm2, sixel) the field is pixels; elsewhere it is the
glyphs from `atlas.txt`.

Until you register arenas (step 6), `arenas/1` offers one world of the player's own:

```elixir
def arenas(_props) do
  case Arenas.list() do
    [] -> [%{id: :own, name: "A cistern of your own", world: {Game, [hz: 30]}, players: 0, humans: []}]
    arenas -> arenas
  end
end
```

A world given as `{module, opts}` is started by the client for this player alone, and
stopped when they leave; `p` pauses it.

## 5. Sound

Events become sounds through one function:

```elixir
def sounds, do: &Cistern.Sound.voice/1

def voice({:catch, :drop_gold}), do: chime([880.0, 1318.5, 1760.0])
def voice({:catch, _kind}), do: chime([659.3, 987.8])
def voice(:splash), do: Voice.new(shape: :noise, cutoff: 0.3, envelope: Envelope.hit(0.25), gain: 0.35)
def voice(_event), do: nil
```

A `TuningFork.Voice` is a synthesised sound: a shape, a pitch, an envelope. A list of
`{delay_ms, voice}` is a run of them. Events carrying a position — `{:catch, kind, pos}`
— are placed: `listener/1` says where the player is, and the sound fades with distance
and pans by side.

Music is a piece with sections and layers, and a cue the game gives from its view:

```elixir
def music, do: Cistern.Sound.pieces()

def cue(%{drops: drops}, :arena), do: Cistern.Sound.cue(length(drops))
def cue(_view, _screen), do: nil
```

`pieces/0` declares `"rain"`: 96 bpm, two layers, `calm` and `busy` sections, each
layer a `TuningFork.Score` written with `TuningFork.Part`. The cue names the section for
the moment — `busy` when more than three drops are in the air — and the engine switches
on the next bar boundary. The second clause is the other screens — the title, the lobby,
the settings — where this game plays nothing.

## 6. More players

A world is a process: `Cauldron2D.World` runs the game at a fixed rate, takes input from
players in their own processes, and sends each their view every tick. The client started
one for you in step 4. To share worlds, register **arenas**:

```elixir
Arenas.register(:yard, game: Game, hz: 30, name: "The yard", note: "everyone in one cistern")

Arenas.register(:contest,
  game: Game,
  hz: 30,
  name: "Against the machine",
  note: "a robot catches beside you",
  children: fn %{world: world} -> [{Robot, brain: Brain, world: world, number: 1}] end
)
```

An arena is a world that starts when the first player joins its name and stops after a
while with nobody in it. The lobby lists them — `arenas/1` returns
`Cauldron2D.Arenas.list/0` — with who is in each, updated as players come and go.
`children` are processes started beside the world: here a computer player.

A robot is a brain module the engine drives on a cadence set by its skill:

```elixir
defmodule Cistern.Brain do
  @behaviour Cauldron2D.Robot

  def init(_opts), do: nil

  def decide(%{me: me, drops: drops}, memory, _clock) do
    held =
      case Enum.max_by(drops, & &1.y, fn -> nil end) do
        nil -> MapSet.new()
        %{x: x} when x < me.x + 0.5 -> MapSet.new([:left])
        %{x: x} when x > me.x + 0.5 -> MapSet.new([:right])
        _under -> MapSet.new()
      end

    {%{held: held, aim: nil}, memory}
  end

  def gone?(%{me: me, misses_allowed: allowed}), do: me == nil or me.misses >= allowed
end
```

It is given the same view a player gets and answers with the same input a player sends.
Nothing in the game knows which buckets are people.

Arenas live in the VM that registered them, so two players share "The yard" when
they reach the same VM: over ssh, with `Cauldron2D.Drafter.Server` serving the game and
each player's terminal connecting to it, or in the browser (step 7). A second `mix
cistern` in another terminal is a second VM with cisterns of its own.

## 7. A browser

The browser front end is a Phoenix channel and a plug of pages. A socket and a channel
module name the game:

```elixir
defmodule Cistern.Web.Socket do
  use Cauldron2D.Net.Socket, channel: Cistern.Web.Channel, verify: {Cistern.Web, :verify}
end

defmodule Cistern.Web.Channel do
  use Cauldron2D.Net.Channel, game: Cistern.Client
end
```

`verify/1` is given the connect params and answers `{:ok, %{username: name}}` or
`:error`. The pages go on a router:

```elixir
forward "/play", to: Cauldron2D.Net.Pages,
  init_opts: [game: Cistern.Client, username: &Cistern.Web.username/1]
```

and the endpoint mounts the socket and the router:

```elixir
defmodule Cistern.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :cistern

  socket "/socket", Cistern.Web.Socket, websocket: true, longpoll: false
  plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason
  plug Cistern.Web.Router
end
```

`mix cistern.serve` starts it on port 4300. `/play` is the title, `/play/lobby` the
arenas, `/play/arena/yard` the field: the pages ship `cauldron.js`, which joins the
channel, draws the frames on a canvas from the atlas served as `atlas.png`, sends the
keys and the pointer as input, and plays the sound the server mixes for this player.
The same game, the same arenas, the same robots.

## 8. A window

```elixir
Cauldron2D.Wx.Client.run(game: Cistern.Client, username: "alice")
```

That is `mix cistern.desktop`: a wx window with the same screens as the terminal
client, drawing the sheet at `:scale` pixels a pixel. It joins the arenas on this node,
or a server's over its socket with the `:link` option.

## 9. Replays, numbers and traces

A world started with `record: true` keeps a `Cauldron2D.Replay` of every join and every
input, tick by tick:

```elixir
replay = Cauldron2D.World.replay(world)
state = Cauldron2D.Replay.run(replay, Cistern.Game, [seed: 7], 1 / 30)
```

Because the game is pure and its randomness is in the state, running the record again
reaches the same state. `Cauldron2D.Replay.Viewer` plays one back on a clock, sending a
watcher the frames a recorded player saw.

`Cauldron2D.Tuning` from step 1 is also what a settings page shows: `describe/1` lists
every setting with its value, limits and text; `step/3` moves one by a twentieth of its
range. Carom binds keys to that.

`CAULDRON_TRACE=1 mix cistern` writes a trace of every key, every input sent and every
frame received; `mix cauldron.report --from key --to frame` tells you how long the game
takes to answer.

## 10. Where next

Three games in the repository use everything above in different ways:

- **Carom** — an Arkanoid. Its art is drawn in code with `FrenchCurve.Draw`; its physics
  is `Cauldron2D.Collision`; its tuning keys change the paddle and the ball while you
  play; its music is five pieces, one a level.
- **Scriber** — a roguelike. Turn-based: its world runs with `tick: :on_input`, so it
  steps only when a key arrives. It has screens of its own — a console with a shell-like
  prompt — so it runs its own `Drafter.App` and starts the world itself rather than
  using the ready-made client. Its creatures hunt by sound.
- **ExPilot** — a multiplayer XPilot. Ships from an outline turned to every heading with
  `Linocut.headings/3`; maps in XPilot's own file format through `Cauldron2D.Map`; a
  server over ssh with accounts; arenas on other nodes and other servers joined through
  `Cauldron2D.Net.Remote`; a ledger of results.

The module documentation is the reference for each piece; this guide is the order to
read it in.
