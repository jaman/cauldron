defmodule GpuShowcase.Application do
  @moduledoc """
  Starts what `config :gpu_showcase, start:` names:

    * `nil` (development) — nothing; `mix showcase` and `mix spheres` run the examples
    * `:desktop` (the desktop release) — opens the showcase as the program starts, with
      the arguments in `SHOWCASE_ARGS` (as `mix showcase` takes them), and stops the
      program when its window closes
    * `{:child, module}` (a phone build) — starts `module`, the showcase on the phone
      (`GpuShowcase.Mobile`)
  """

  use Application

  @impl Application
  def start(_type, _args) do
    children = children(Application.get_env(:gpu_showcase, :start))
    Supervisor.start_link(children, strategy: :one_for_one, name: GpuShowcase.Supervisor)
  end

  defp children(nil), do: []
  defp children(:desktop), do: [{Task, &run_and_stop/0}]
  defp children({:child, module}), do: [{module, []}]

  defp run_and_stop do
    "SHOWCASE_ARGS" |> System.get_env("") |> OptionParser.split() |> GpuShowcase.Showcase.run()
    System.stop()
  end
end
