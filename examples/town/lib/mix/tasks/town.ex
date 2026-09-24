defmodule Mix.Tasks.Town do
  @shortdoc "Walk the town in this terminal"

  @moduledoc """
  Run the terminal client on the town.

      mix town
      mix town --name alice
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      props: %{game: Town.Client, username: Keyword.get(opts, :name, "player")}
    )
  end
end
