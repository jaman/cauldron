defmodule Mix.Tasks.Parade do
  @shortdoc "Walk the parade courtyard in this terminal"

  @moduledoc """
  Run the terminal client on the parade.

      mix parade
      mix parade --name alice
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      props: %{game: Parade.Client, username: Keyword.get(opts, :name, "player")}
    )
  end
end
