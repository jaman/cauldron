defmodule Mix.Tasks.Greenware do
  @shortdoc "Play Greenware in this terminal"

  @moduledoc """
  Run the terminal client.

      mix greenware
      mix greenware --name mender
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv), do: Cauldron2D.Drafter.Play.run(Greenware.Client, argv, name: "mender")
end
