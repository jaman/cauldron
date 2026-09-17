defmodule Mix.Tasks.Cistern.Serve do
  @shortdoc "Serve Cistern to browsers on port 4300"

  @moduledoc """
  Start the endpoint with the shared arenas registered, and keep it up.

      mix cistern.serve
  """

  use Mix.Task

  alias Cistern.Web.Endpoint

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")
    Cistern.Arenas.register()
    Cistern.Art.install()
    {:ok, _pubsub} = Phoenix.PubSub.Supervisor.start_link(name: Cistern.PubSub)
    {:ok, _endpoint} = Endpoint.start_link(http: [port: 4300], server: true)
    Mix.shell().info("Cistern at http://localhost:4300/play")
    Process.sleep(:infinity)
  end
end
