defmodule Mix.Tasks.Megablast do
  @shortdoc "Fly the parallax lane in this terminal"

  @moduledoc """
  Run the terminal client on the chitin lane.

      mix megablast
      mix megablast --name alice
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      props: %{game: Megablast.Client, username: Keyword.get(opts, :name, "pilot")}
    )
  end
end
