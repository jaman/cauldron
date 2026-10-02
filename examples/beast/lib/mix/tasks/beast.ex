defmodule Mix.Tasks.Beast do
  @shortdoc "Run the parallax side-scroller in this terminal"

  @moduledoc """
  Run the terminal client on the red plain.

      mix beast
      mix beast --name alice
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      props: %{game: Beast.Client, username: Keyword.get(opts, :name, "runner")}
    )
  end
end
