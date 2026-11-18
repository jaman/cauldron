defmodule Mix.Tasks.Spheres do
  @shortdoc "Two thousand metal and plastic spheres, as a load test"

  @moduledoc """
  Two thousand metal and plastic spheres, as a load test. Runs `GpuShowcase.Spheres.run/1` with the task's arguments; that module's
  documentation lists them.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    GpuShowcase.Spheres.run(args)
  end
end
