defmodule Cauldron2D.Game do
  @moduledoc """
  What a game gives `Cauldron2D.World` to run: a pure value and the callbacks that change it.

      defmodule MyGame do
        @behaviour Cauldron2D.Game

        def init(opts), do: ...
        def join(state, player_id, props), do: {:ok, state}
        def leave(state, player_id), do: state
        def handle_input(state, player_id, %{held: held, aim: aim}), do: state
        def step(state, dt), do: state
        def view(state, player_id), do: ...
        def drain_events(state), do: {events, state}
      end

  Every callback is pure. `step/2` is called once per fixed tick with `dt` in seconds;
  `handle_input/3` before the tick for each player whose input changed; `view/2` after it
  for each player, and what it returns is sent to that player; `drain_events/1` after it,
  once, and the events go to every player. Nothing here reads a clock, and a game built
  with the same options and given the same calls in the same order runs identically.

  `join/3`'s `props` are the game's to define. The clients in the `cauldron_2d_*`
  packages pass `:username` (the player's name as a string) and whatever the game's own
  `join_props` callback adds; a game that wants teams, spectators or anything else names
  those props itself and reads them here.

  A world on another machine can follow this one (`Cauldron2D.World`'s `:follow`),
  running the same calls on its own copy of the state. Three optional callbacks serve it:

    * `export/1` — what of the state a follower starts from, with what the follower's
      machine has of its own (the game's data, its pictures) left out. Default: the
      whole state
    * `restore/1` — the state a follower runs, from what `export/1` gave, filled in
      from this machine. Default: as it came
    * `checksum/1` — what host and follower compare to know their states agree, the
      parts the steps decide. Default: `:erlang.phash2/1` of the whole state

  A world playing with rollback (`Cauldron2D.World.Rollback`) also reads the optional
  `input_delay/1` after its steps: the frames its own players' input is stamped ahead,
  or `nil` to keep the delay it has. Both worlds run the same state, so both take the
  same delay.
  """

  @type state :: term()
  @type player_id :: term()

  @typedoc """
  A player's input: `Cauldron2D.Input.state/1`'s map, which a client looking through an
  eye adds `:heading` to — where the player looks, in radians with `0` along `+x` — so
  a game can walk `:up` along it, `:down` against it and `:left` and `:right` across it.
  """
  @type input :: %{
          required(:held) => MapSet.t(atom()),
          required(:aim) => {number(), number()} | nil,
          optional(:strength) => %{atom() => float()},
          optional(:heading) => float()
        }

  @callback init(keyword()) :: state()
  @callback join(state(), player_id(), map()) :: {:ok, state()} | {:error, term()}
  @callback leave(state(), player_id()) :: state()
  @callback handle_input(state(), player_id(), input()) :: state()
  @callback step(state(), float()) :: state()
  @callback view(state(), player_id()) :: term()
  @callback drain_events(state()) :: {[term()], state()}
  @callback export(state()) :: term()
  @callback restore(term()) :: state()
  @callback checksum(state()) :: term()

  @callback input_delay(state()) :: pos_integer() | nil

  @optional_callbacks export: 1, restore: 1, checksum: 1, input_delay: 1
end
