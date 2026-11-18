defmodule Mix.Tasks.Cauldron.Sfx.Web do
  @shortdoc "Edits a game's sound effects in a browser"

  @moduledoc """
  Opens the sound-effect editor in a browser.

      mix cauldron.sfx.web priv/sfx/sfx.json
      mix cauldron.sfx.web --port 4100 --out priv/sfx/sfx.json

  With no file, the editor opens on `Cauldron.SFX.starter/0`.

  ## Options

    * `--port N` — the port to listen on, default 4040
    * `--out PATH` — where `write` writes, default the file given, or `sfx.json`
  """

  use Mix.Task

  alias Cauldron.SFX.Web.Serve

  @switches [port: :integer, out: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(argv, strict: @switches)
    port = Keyword.get(opts, :port, 4040)
    path = List.first(argv)

    {:ok, _pid} =
      Serve.serve(
        port: port,
        bank: path,
        out: Keyword.get(opts, :out) || path || "sfx.json"
      )

    Mix.shell().info("SFX editor: http://localhost:#{port}")
    Process.sleep(:infinity)
  end
end
