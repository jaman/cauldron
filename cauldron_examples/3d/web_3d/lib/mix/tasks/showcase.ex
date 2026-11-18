defmodule Mix.Tasks.Showcase do
  @shortdoc "The showcase courtyard served to a browser at http://localhost:4400"

  @moduledoc """
  The showcase courtyard served to a browser at http://localhost:4400. Runs `Web3D.Showcase.run/1` with the task's arguments; that module's documentation
  lists them.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Web3D.Showcase.run(args)
  end
end
