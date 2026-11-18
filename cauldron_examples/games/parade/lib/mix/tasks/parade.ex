defmodule Mix.Tasks.Parade do
  @shortdoc "Walk the parade courtyard in this terminal"

  @moduledoc """
  Run the terminal client on the parade.

      mix parade
      mix parade --name alice

  The flags are `Cauldron2D.Drafter.Play`'s: `--name`, `--mute`, `--picture`, `--trace`.
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv), do: Play.run(Parade.Client, argv, name: "player")
end
