defmodule Mix.Tasks.Cauldron.Sectors do
  @shortdoc "Edit a sector map in the terminal"

  @moduledoc """
  Open `Cauldron2D.Easel.Drafter.SectorEditor` on a sector document, creating it on the
  first save if it does not exist.

      mix cauldron.sectors priv/maps/hall.json
      mix cauldron.sectors priv/maps/hall.json --grid 16

  ## Options

    * `--grid` — the snap for a new document, in world units. Default `32`
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, [path | _rest], _invalid} = OptionParser.parse(args, strict: [grid: :integer])
    Mix.Task.run("app.start")

    Drafter.run(Cauldron2D.Easel.Drafter.SectorEditor,
      props: %{path: path, grid: Keyword.get(opts, :grid, 32)}
    )
  end
end
