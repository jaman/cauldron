defmodule Mix.Tasks.CisternComplete do
  @shortdoc "Play Cistern, finished, in this terminal"

  @moduledoc """
  Run the terminal client with the versus world registered.

      mix cistern_complete
      mix cistern_complete --name alice

  The flags are `Cauldron2D.Drafter.Play`'s: `--name`, `--mute`, `--picture`, `--trace`.
  """

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run(argv),
    do:
      Play.run(CisternComplete.Client, argv,
        name: "keeper",
        before: &CisternComplete.Worlds.register/0
      )
end
