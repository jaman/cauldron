defmodule Mix.Tasks.Beast do
  @shortdoc "Play Beast in this terminal"

  @moduledoc """
  Run the terminal client.

      mix beast
      mix beast --name alice

  The flags are `Cauldron2D.Drafter.Play`'s: `--name`, `--mute`, `--picture`, `--trace`.
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv), do: Play.run(Beast.Client, argv, name: "beast")
end
