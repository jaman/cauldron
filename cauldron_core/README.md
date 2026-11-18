# Cauldron

Cauldron is the engine every Cauldron game runs on, with no way of drawing in it. You write a
game as a value and a few pure functions. A world runs it at a fixed tick for any number
of players, on one machine or across several. Input, menus, sound, saving, high scores
and the client side every front end shares come with it.

How a game looks is another package's:

* [`cauldron_2d`](https://hexdocs.pm/cauldron_2d) draws tile worlds, sprites and 2D
  projections, in a terminal, a desktop window or a browser.
* [`cauldron_gpu`](https://hexdocs.pm/cauldron_gpu) draws 3D scenes on the graphics card.

## Installation

Add the package that draws your kind of game; it brings this one with it:

```elixir
def deps do
  [{:cauldron_2d, "~> 0.4"}]
end
```

## A game

A game implements `Cauldron.Game`. Every callback is pure:

```elixir
defmodule Walk.Game do
  @behaviour Cauldron.Game

  @speeds %{left: -4.0, right: 4.0}

  @impl true
  def init(_opts), do: %{players: %{}}

  @impl true
  def join(state, id, _props), do: {:ok, put_in(state.players[id], %{x: 0.0, held: MapSet.new()})}

  @impl true
  def leave(state, id), do: %{state | players: Map.delete(state.players, id)}

  @impl true
  def handle_input(state, id, %{held: held}), do: put_in(state.players[id].held, held)

  @impl true
  def step(state, dt) do
    players =
      Map.new(state.players, fn {id, player} ->
        speed = Enum.sum(for action <- player.held, do: Map.get(@speeds, action, 0.0))
        {id, %{player | x: player.x + speed * dt}}
      end)

    %{state | players: players}
  end

  @impl true
  def view(state, id), do: %{me: state.players[id]}

  @impl true
  def drain_events(state), do: {[], state}
end
```

`Cauldron.World` runs it, and `Cauldron.Player` joins, sends input and receives views:

```elixir
{:ok, world} = Cauldron.World.start_link(game: Walk.Game, hz: 30)
:ok = Cauldron.Player.join(world, :alice, %{})
Cauldron.Player.input(world, :alice, %{held: MapSet.new([:right]), aim: nil})
```

`Cauldron.Test` drives a game in a test with no process and no clock.

## Putting a game in front of a player

A front end (a terminal, a desktop window, a browser, a phone) reads what a game gives it
through `Cauldron.Client.Game`: its title, actions and keymaps, its worlds, a scene for
each view, its hud, sound and music, its menu. How the scene is drawn and how the player
looks at it is the game's view, a `Cauldron.Client.View`, which the drawing package
provides: a 2D game writes `use Cauldron2D.Client.Game`.

## What is in it

| Area | Modules |
| --- | --- |
| Running games | `Cauldron.Game`, `Cauldron.World`, `Cauldron.Worlds`, `Cauldron.Player`, `Cauldron.Robot`, `Cauldron.Replay`, `Cauldron.Test` |
| Play across machines | `Cauldron.Link` (rollback), `Cauldron.Distribution`, `Cauldron.Beacon` |
| Clients | `Cauldron.Client.Game`, `Cauldron.Client.View`, `Cauldron.Client.Stage`, `Cauldron.Client.Party`, `Cauldron.Client.Controls`, `Cauldron.Menu`, `Cauldron.Front` |
| Input | `Cauldron.Input`, `Cauldron.Input.Pad`, `Cauldron.Presses` |
| Game state | `Cauldron.Rng`, `Cauldron.Timers`, `Cauldron.Tuning`, `Cauldron.Tween`, `Cauldron.States`, `Cauldron.Thinkers`, `Cauldron.Effects`, `Cauldron.Moves` |
| Sound | `Cauldron.Audio` (playing), `Cauldron.Audio.Music` (pieces and cues), `Cauldron.Audio.Sink` (where sound goes), `Cauldron.Audio.Voice`, `Envelope`, `Filter`, `Curve`, `Sample` (making sounds), `Cauldron.Audio.Score`, `Part` (writing music), `Cauldron.Audio.Decoder` (MP3, Ogg, FLAC, WAV) |
| Files | `Cauldron.Paths`, `Cauldron.Save`, `Cauldron.Scores`, `Cauldron.Ledger`, `Cauldron.Launch`, `Cauldron.Trace` |

## Configuration

* `config :cauldron_core, sweeper: [idle_after: seconds, every: seconds]` — how long a world
  with no human in it runs before `Cauldron.Worlds.Sweeper` stops it, and how often it looks
* `config :cauldron_core, beacon_port: n` — the UDP port `Cauldron.Beacon` calls on
