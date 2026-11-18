defmodule Mix.Tasks.Courtyard.Serve do
  @shortdoc "Serves the courtyard to browsers and desktops over the network"

  @moduledoc """
  Serves the courtyard over the network at `http://localhost:4310/play`. Each client
  draws the scene with its own renderer (`Cauldron3D.Net.Drawer`): a browser with
  three.js, a desktop or phone client with its graphics card.

      mix courtyard.serve [--port 4310]
  """

  use Mix.Task

  alias Cauldron2D.Net.Serve

  @impl Mix.Task
  def run(argv), do: Serve.run(Courtyard.Client, argv, port: 4310, drawer: Cauldron3D.Net.Drawer)
end
