defmodule Mix.Tasks.Cistern do
  @shortdoc "Play Cistern in this terminal"

  @moduledoc """
  Run the terminal client with the shared worlds registered.

      mix cistern
      mix cistern --name alice

  The flags are `Cauldron2D.Drafter.Play`'s: `--name`, `--mute`, `--picture`, `--trace`.
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv),
    do:
      Play.run(Cistern.Client, argv,
        name: "player",
        before: &Cistern.Worlds.register/0
      )
end
