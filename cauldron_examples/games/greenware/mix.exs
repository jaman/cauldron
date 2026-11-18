defmodule Greenware.MixProject do
  use Mix.Project

  @native [:ios, :android, :macos]

  def project do
    [
      app: :greenware,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.target()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [greenware: [include_erts: false, strip_beams: true]],
      cauldron_native: [
        name: "Greenware",
        id: "io.github.jaman.greenware",
        orientation: :landscape
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:host), do: ["lib"]
  defp elixirc_paths(_target), do: ["lib/greenware"]

  defp deps do
    [
      {:cauldron_2d, path: "../../../cauldron_2d"},
      {:cauldron_2d_drafter, path: "../../../cauldron_2d_drafter", targets: :host},
      {:cauldron_2d_wx, path: "../../../cauldron_2d_wx", targets: :host},
      {:cauldron_2d_native, path: "../../../cauldron_2d_native", targets: @native},
      {:cauldron_native, path: "../../../cauldron_native", runtime: Mix.target() in @native}
    ]
  end
end
