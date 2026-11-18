defmodule Mix.Tasks.Town do
  @shortdoc "Walk the town in this terminal"

  @moduledoc """
  Run the terminal client on the town.

      mix town
      mix town --name alice

  The flags are `Cauldron2D.Drafter.Play`'s: `--name`, `--mute`, `--picture`, `--trace`.
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv), do: Play.run(Town.Client, argv, name: "player")
end
