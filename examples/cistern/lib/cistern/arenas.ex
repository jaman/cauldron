defmodule Cistern.Arenas do
  @moduledoc """
  The shared arenas: two cisterns every player on this node can join, one of them with
  a robot in it, registered with `Cauldron2D.Arenas` so the lobby lists them and a
  world starts when the first player joins.
  """

  alias Cauldron2D.{Arenas, Robot}
  alias Cistern.{Brain, Game}

  @doc "Register the arenas."
  @spec register() :: :ok
  def register do
    Arenas.register(:yard, game: Game, hz: 30, name: "The yard", note: "everyone in one cistern")

    Arenas.register(:contest,
      game: Game,
      hz: 30,
      name: "Against the machine",
      note: "a robot catches beside you",
      children: fn %{world: world} -> [{Robot, brain: Brain, world: world, number: 1}] end
    )
  end
end
