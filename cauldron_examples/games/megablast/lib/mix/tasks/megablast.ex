defmodule Mix.Tasks.Megablast do
  @shortdoc "Fly Megablast in this terminal"

  @moduledoc """
  Run the terminal client.

      mix megablast
      mix megablast --name alice

  The flags are `Cauldron2D.Drafter.Play`'s: `--name`, `--mute`, `--picture`, `--trace`.
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv), do: Play.run(Megablast.Client, argv, name: "pilot")
end
