defmodule Mix.Tasks.Showcase do
  @shortdoc "A lit courtyard: spheres, turning crates, a sun and lamps; fly through it"

  @moduledoc """
  A lit courtyard: spheres, turning crates, a sun and lamps; fly through it. Runs `GpuShowcase.Showcase.run/1` with the task's arguments; that module's
  documentation lists them.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    GpuShowcase.Showcase.run(args)
  end
end
