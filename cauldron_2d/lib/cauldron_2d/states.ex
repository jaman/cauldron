defmodule Cauldron2D.States do
  @moduledoc """
  State tables: an actor's animation and behaviour as data, each state a picture shown for
  a number of ticks, an action run on entering it, and the state that follows.

      table = %{
        stand: %{picture: {"TROO", 0}, tics: 10, action: :look, next: :stand_b},
        stand_b: %{picture: {"TROO", 1}, tics: 10, action: :look, next: :stand},
        die: %{picture: {"TROO", 8}, tics: 8, action: :scream, next: :dead},
        dead: %{picture: {"TROO", 12}, tics: -1, action: nil, next: nil}
      }

      actor = Cauldron2D.States.enter(actor, table, :stand, &MyGame.act/2)
      actor = Cauldron2D.States.tick(actor, table, &MyGame.act/2)

  An actor is a map; entering a state sets its `:state`, `:tics` and `:picture` and then
  runs `act.(actor, action)` with the state's action, which returns the actor and may
  itself `enter/4` another state. A state of zero ticks is passed straight through to the
  next. A state of `-1` ticks lasts until something enters another. Entering `nil`, or a
  `next` of `nil`, sets `:state` to `nil`: the actor is finished and the caller removes it.

  `picture` and `action` are the game's terms; the table only orders them. `tick/3`
  counts a state down by one tick and enters the next when it runs out.
  """

  @type name :: term()
  @type state :: %{picture: term(), tics: integer(), action: term(), next: name() | nil}
  @type table :: %{name() => state()}
  @type actor :: %{
          optional(:state) => name() | nil,
          optional(:tics) => integer(),
          optional(atom()) => term()
        }

  @doc "Enter state `name`, running actions and passing through zero-tick states."
  @spec enter(actor(), table(), name() | nil, (actor(), term() -> actor())) :: actor()
  def enter(actor, _table, nil, _act), do: Map.merge(actor, %{state: nil, tics: -1})

  def enter(actor, table, name, act) do
    state = Map.fetch!(table, name)
    actor = Map.merge(actor, %{state: name, tics: state.tics, picture: state.picture})
    actor = if state.action == nil, do: actor, else: act.(actor, state.action)

    cond do
      actor.state == nil -> actor
      actor.state == name and actor.tics == 0 -> enter(actor, table, state.next, act)
      true -> actor
    end
  end

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
