defmodule Mix.Tasks.Greenware.Desktop do
  @shortdoc "Play Greenware in a desktop window"

  @moduledoc """
  Run the wx client.

      mix greenware.desktop
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    Cauldron2D.Wx.Client.run(
      game: Greenware.Client,
      username: "mender",
      size: {1280, 720},
      view_size: {1280, 720},
      hud: :none,
      scale: 1
    )
  end
end
