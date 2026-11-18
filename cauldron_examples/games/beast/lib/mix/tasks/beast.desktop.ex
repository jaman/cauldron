defmodule Mix.Tasks.Beast.Desktop do
  @shortdoc "Play Beast in a window"

  @moduledoc """
  Open the desktop window.

      mix beast.desktop
      mix beast.desktop --name alice
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [name: :string])
    Mix.Task.run("app.start")
    Cauldron2D.Wx.Client.run(game: Beast.Client, username: Keyword.get(opts, :name, "player"))
  end
end
