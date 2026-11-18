defmodule Mix.Tasks.Crossing do
  @shortdoc "Cross the road and the river in this terminal"

  @moduledoc """
  Run the terminal client on the crossing.

      mix crossing
      mix crossing --name alice

  The flags are `Cauldron2D.Drafter.Play`'s: `--name`, `--mute`, `--picture`, `--trace`.
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv), do: Play.run(Crossing.Client, argv, name: "frog")
end
