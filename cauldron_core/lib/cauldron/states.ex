defmodule Cauldron.States do
  @moduledoc """
  State tables: an actor's animation and behaviour as data, each state a picture shown for
  a number of ticks, an action run on entering it, and the state that follows.

      table = %{
        stand: %{picture: {"TROO", 0}, tics: 10, action: :look, next: :stand_b},
        stand_b: %{picture: {"TROO", 1}, tics: 10, action: :look, next: :stand},
        die: %{picture: {"TROO", 8}, tics: 8, action: :scream, next: :dead},
        dead: %{picture: {"TROO", 12}, tics: -1, action: nil, next: nil}
      }

      actor = Cauldron.States.enter(actor, table, :stand, &MyGame.act/2)
      actor = Cauldron.States.tick(actor, table, &MyGame.act/2)

  An actor is a map; entering a state sets its `:state`, `:tics` and `:picture` and then
  runs `act.(actor, action)` with the state's action, which returns the actor and may
  itself `enter/4` another state. A state of zero ticks is passed straight through to the
  next. A state of `-1` ticks lasts until something enters another. Entering `nil`, or a
  `next` of `nil`, sets `:state` to `nil`: the actor is finished and the caller removes it.

  `picture` and `action` are the game's terms; the table only orders them. `tick/3`
  counts a state down by one tick and enters the next when it runs out.

  A state may give `seconds:` in place of `tics:`, for a game stepped in seconds:
  `step/4` runs it down by `dt` and enters the next when it runs out, a state of `0`
  seconds is passed straight through, and one of `-1` lasts until something enters
  another. Entering any state sets the actor's `:since` to `0.0`, and `step/4` adds to
  it: the seconds spent in the state, to pick an animation frame by.

      table = %{
        windup: %{picture: :raise, seconds: 0.2, action: nil, next: :swing},
        swing: %{picture: :swing, seconds: 0.1, action: :hit, next: :rest},
        rest: %{picture: :stand, seconds: -1, action: nil, next: nil}
      }

      goblin = Cauldron.States.step(goblin, table, dt, &MyGame.act/2)
  """

  @type name :: term()
  @type state :: %{
          required(:picture) => term(),
          optional(:tics) => integer(),
          optional(:seconds) => number(),
          required(:action) => term(),
          required(:next) => name() | nil
        }
  @type table :: %{name() => state()}
  @type actor :: %{
          optional(:state) => name() | nil,
          optional(:tics) => integer(),
          optional(:left) => number() | nil,
          optional(:since) => number(),
          optional(atom()) => term()
        }

  @doc "Enter state `name`, running actions and passing through zero-tick states."
  @spec enter(actor(), table(), name() | nil, (actor(), term() -> actor())) :: actor()
  def enter(actor, _table, nil, _act), do: Map.merge(actor, %{state: nil, tics: -1})

  def enter(actor, table, name, act) do
    state = Map.fetch!(table, name)

    actor =
      Map.merge(actor, %{
        state: name,
        tics: Map.get(state, :tics, -1),
        left: Map.get(state, :seconds),
        since: 0.0,
        picture: state.picture
      })

    actor = if state.action == nil, do: actor, else: act.(actor, state.action)

    cond do
      actor.state == nil -> actor
      actor.state == name and passed?(actor) -> enter(actor, table, state.next, act)
      true -> actor
    end
  end

  @doc "`dt` seconds of a table given in seconds: the state run down, the next entered when it runs out."
  @spec step(actor(), table(), number(), (actor(), term() -> actor())) :: actor()
  def step(%{state: nil} = actor, _table, _dt, _act), do: actor

  def step(%{left: left} = actor, table, dt, act) when is_number(left) and left >= 0 do
    actor = %{actor | since: actor.since + dt}

    if left - dt <= 0,
      do: enter(actor, table, Map.fetch!(table, actor.state).next, act),
      else: %{actor | left: left - dt}
  end

  def step(actor, _table, dt, _act), do: Map.update(actor, :since, dt, &(&1 + dt))

  defp passed?(%{tics: 0}), do: true
  defp passed?(%{left: left}) when left == 0, do: true
  defp passed?(_actor), do: false

  @doc "One tick: count the state down and enter the next when it runs out."
  @spec tick(actor(), table(), (actor(), term() -> actor())) :: actor()
  def tick(%{state: nil} = actor, _table, _act), do: actor
  def tick(%{tics: -1} = actor, _table, _act), do: actor

  def tick(%{state: name, tics: tics} = actor, table, act) do
    if tics - 1 <= 0,
      do: enter(actor, table, Map.fetch!(table, name).next, act),
      else: %{actor | tics: tics - 1}
  end
end
