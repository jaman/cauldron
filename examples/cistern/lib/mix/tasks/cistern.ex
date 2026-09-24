defmodule Mix.Tasks.Cistern do
  @shortdoc "Play Cistern in this terminal"

  @moduledoc """
  Run the terminal client with the shared worlds registered.

      mix cistern
      mix cistern --name alice
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    Cistern.Worlds.register()

    Drafter.run(Cauldron2D.Drafter.Client,
      props: %{game: Cistern.Client, username: Keyword.get(opts, :name, "player")}
    )
  end
end
