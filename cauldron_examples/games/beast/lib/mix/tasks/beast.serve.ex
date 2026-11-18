defmodule Mix.Tasks.Beast.Serve do
  @shortdoc "Serve Beast to browsers"

  @moduledoc """
  Serve the game at `http://localhost:4310/play`.

      mix beast.serve
      mix beast.serve --port 4400 --drawing client

  The flags are `Cauldron2D.Net.Serve`'s: `--port`, `--drawing`.
  """

  use Mix.Task

  alias Cauldron2D.Net.Serve

  @impl Mix.Task
  def run(argv), do: Serve.run(Beast.Client, argv, port: 4310)
end
