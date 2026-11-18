# Testing

A Cauldron game is a value and pure functions, so it can be driven with no world
process and no clock. `Cauldron.Test` joins players, holds actions, runs ticks, and reads
views and events.

## The driver

```elixir
driver = Cauldron.Test.new(Walk.Game, game_opts: [seed: 1], hz: 10)
```

`new/2` calls the game's `init/1` with `:game_opts` and keeps a `dt` of `1 / hz`. The
driver is a struct: the game module, its state, the input waiting for the next tick, the
events drained so far, and how many ticks have run.

| Function | Does |
| --- | --- |
| `Cauldron.Test.new/2` | A driver for a game module |
| `Cauldron.Test.join/3` | Join a player, `{:ok, driver}` or the game's `{:error, reason}` |
| `Cauldron.Test.leave/2` | Remove a player |
| `Cauldron.Test.hold/5` | What a player holds from the next tick |
| `Cauldron.Test.tick/2` | Run ticks |
| `Cauldron.Test.until/3` | Tick until a condition holds, or a limit is reached |
| `Cauldron.Test.view/2` | The game's view for a player now |
| `Cauldron.Test.events/1` | Every event drained so far, oldest first |
| `Cauldron.Test.state/1` | The game's state |
| `Cauldron.Test.tick_count/1` | How many ticks have run |

## What a tick does

One tick is what `Cauldron.World` does on one step:

1. the input held since the last tick is applied with `handle_input/3`;
2. the game steps once with `dt`;
3. `drain_events/1` is called and its events are added to the driver's.

`hold/5` is input for the *next* tick, not a switch that stays down. The driver clears
its pending input after every tick, as a world applies the input it has and waits for
more. A game that wants an action to keep acting keeps it in its own state, in
`handle_input/3`, and reads that state in `step/2`. A test that wants the input to
change must call `hold` again.

## A game to test

```elixir
defmodule Walk.Game do
  @behaviour Cauldron.Game

  @speeds %{left: -4.0, right: 4.0}
  @goal 3.0

  @impl true
  def init(_opts), do: %{players: %{}, events: []}

  @impl true
  def join(state, id, _props) do
    player = %{x: 0.0, held: MapSet.new(), finished?: false}
    {:ok, put_in(state.players[id], player)}
  end

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

    finished =
      for {id, player} <- players,
          player.x >= @goal,
          not player.finished?,
          do: {:finished, id}

    players =
      Map.new(players, fn {id, player} ->
        {id, %{player | finished?: player.x >= @goal}}
      end)

    %{state | players: players, events: state.events ++ finished}
  end

  @impl true
  def view(state, id), do: %{me: Map.fetch!(state.players, id)}

  @impl true
  def drain_events(state), do: {state.events, %{state | events: []}}
end
```

It has no process, reads no clock and draws nothing.

## The test

```elixir
defmodule Walk.GameTest do
  use ExUnit.Case, async: true

  alias Cauldron.Test

  test "holding right walks the player to the goal" do
    driver = Test.new(Walk.Game, hz: 10)
    {:ok, driver} = Test.join(driver, :alice, %{username: "alice"})

    driver = driver |> Test.hold(:alice, [:right]) |> Test.tick(10)

    assert %{me: %{x: x, finished?: true}} = Test.view(driver, :alice)
    assert_in_delta x, 4.0, 1.0e-6
    assert Test.tick_count(driver) == 10
    assert Test.events(driver) == [{:finished, :alice}]
  end

  test "an action let go stops acting" do
    driver = Test.new(Walk.Game, hz: 10)
    {:ok, driver} = Test.join(driver, :alice, %{username: "alice"})

    driver = driver |> Test.hold(:alice, [:right]) |> Test.tick(3)
    driver = driver |> Test.hold(:alice, []) |> Test.tick(3)

    assert %{me: %{x: x}} = Test.view(driver, :alice)
    assert_in_delta x, 1.2, 1.0e-6
  end

  test "the driver joins the same id twice without a process to refuse it" do
    driver = Test.new(Walk.Game)
    {:ok, driver} = Test.join(driver, :alice, %{})
    assert {:ok, _driver} = Test.join(driver, :alice, %{})
  end
end
```

The second test relies on the game's own state. The first `hold` is delivered at the
first of the three ticks, and the player keeps its held set until the next input
replaces it. The third test shows that the driver does not police ids the way a world
does. `Cauldron.World` refuses an id another process already plays; `join/3` here is the
game's callback.

`hold/5` also takes an aim and how hard each action is held:

```elixir
driver = Cauldron.Test.hold(driver, :alice, [:fire], {120.0, 40.0}, %{fire: 0.5})
```

The aim arrives as `:aim`, and a non-empty strength map as `:strength`, as a client
would send them.

## Waiting for something

`tick/2` runs a fixed number of ticks. When a test does not know how many it needs,
`until/3` runs one at a time until a condition of the driver is true:

```elixir
{:ok, driver} =
  Cauldron.Test.until(
    driver,
    fn driver -> Cauldron.Test.view(driver, :alice).me.finished? end,
    100
  )
```

It returns `{:ok, driver}` or `{:timeout, driver}`, with the driver as far as it got.
A timeout is a failed expectation, not an empty result, so match it and assert on it
rather than ignoring it.

## Reading views and events

`view/2` calls the game's `view/2` on the spot. It is the same function the world would
call, and it costs nothing but the call. `events/1` is every event drained since the
driver was made, oldest first, so events from different ticks are all in one list.
`state/1` is the whole game state, for the assertions a view does not expose.

`view/2` takes an id so a test can see what one player sees, and not another: join two
players, hold different actions, tick once, and compare.

## Files in a test

`Cauldron.Save`, `Cauldron.Scores` and `Cauldron.Ledger` write real files, and
`Cauldron.Paths` reads its environment variables on every call. A test that touches them
should point them at a temporary directory first, and not run asynchronously:

```elixir
setup do
  root = Path.join(System.tmp_dir!(), "walk-test-#{System.unique_integer([:positive])}")
  System.put_env("XDG_DATA_HOME", root)
  System.put_env("XDG_CONFIG_HOME", root)
  on_exit(fn -> File.rm_rf!(root) end)
  :ok
end
```

The game state itself needs nothing of this: a test of the world module never opens a
file.

## Where to go next

| You want to | Read |
| --- | --- |
| Run the same game in a real world | [Worlds and players](worlds-and-players.html) |
| Understand the input a test sends | [Input and menus](input-and-menus.html) |
| Test a save, score or board | [Saving and scores](saving-and-scores.html) |
| Find a word | [Glossary](glossary.html) |
