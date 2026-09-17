defmodule Mix.Tasks.Cistern.Desktop do
  @shortdoc "Play Cistern in a window"

  @moduledoc """
  Open the wx window with the shared arenas registered.

      mix cistern.desktop --name alice
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Cistern.Arenas.register()
    Cauldron2D.Wx.Client.run(game: Cistern.Client, username: Keyword.get(opts, :name, "player"))
  end
end
