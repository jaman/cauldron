defmodule Cistern.Worlds do
  @moduledoc """
  The shared worlds: two cisterns every player on this node can join, one of them with
  a robot in it, registered with `Cauldron2D.Worlds` so the lobby lists them and a
  world starts when the first player joins.
  """

  alias Cauldron2D.{Worlds, Robot}
  alias Cistern.{Brain, Game}

  @doc "Register the worlds."
  @spec register() :: :ok
  def register do
    Worlds.register(:yard, game: Game, hz: 30, name: "The yard", note: "everyone in one cistern")

    Worlds.register(:contest,
      game: Game,
      hz: 30,
      name: "Against the machine",
      note: "a robot catches beside you",
      children: fn %{world: world} -> [{Robot, brain: Brain, world: world, number: 1}] end
    )
  end
end
