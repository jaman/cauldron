defmodule CisternComplete.Worlds do
  @moduledoc "The versus world, a square beside a robot keeper's, registered with `Cauldron.Worlds`."

  alias Cauldron.{Robot, Worlds}
  alias CisternComplete.{Brain, Game}

  @doc "Register the world."
  @spec register() :: :ok
  def register do
    Worlds.register(:cistern_complete_versus,
      game: Game,
      hz: 30,
      name: "Versus the robot",
      note: "a robot keeps the square beside yours",
      children: fn %{world: world} -> [{Robot, brain: Brain, world: world, number: 1}] end
    )
  end
end
