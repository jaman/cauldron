defmodule Mix.Tasks.Cauldron.Play do
  @moduledoc """
  Play a game in this terminal, given its client module.

      mix cauldron.play MyGame.Client
      mix cauldron.play MyGame.Client --name alice --mute --picture native,swap

  The flags are `Cauldron2D.Drafter.Play`'s.
  """
  @shortdoc "Play a game in this terminal"

  use Mix.Task

  alias Cauldron2D.Drafter.Play

  @impl Mix.Task
  def run([client | argv]) do
    Mix.Task.run("app.start")
    game = Module.concat([client])
    Code.ensure_loaded?(game) || Mix.raise("#{client} is not a module in this project")
    Play.run(game, argv)
  end

  def run([]),
    do:
      Mix.raise(
        "usage: mix cauldron.play MyGame.Client [--name NAME] [--mute] [--picture OPTIONS] [--trace FILE]"
      )
end
