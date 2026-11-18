defmodule Cistern.Worlds do
  @moduledoc """
  The shared worlds: two cisterns every player on this node can join, one of them with
  a robot in it, registered with `Cauldron.Worlds` so the lobby lists them and a
  world starts when the first player joins.
  """

  alias Cauldron.{Robot, Worlds}
  alias Cistern.{Brain, Game}

  @doc "Register the worlds."
  @spec register() :: :ok
  def register do
    Worlds.register(:yard,
      game: Game,
      hz: 30,
      name: "The yard",
      note: "every keeper a square, one storm"
    )

    Worlds.register(:contest,
      game: Game,
      hz: 30,
      name: "Against the machine",
      note: "a robot keeps the square beside yours",
      children: fn %{world: world} -> [{Robot, brain: Brain, world: world, number: 1}] end
    )
  end
end
