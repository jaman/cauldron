defmodule Beast.MixProject do
  use Mix.Project

  @mobile [:ios, :tvos, :macos, :android]

  def project do
    [
      app: :beast,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.target()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [beast: [include_erts: false, strip_beams: true]],
      cauldron_native: [name: "Beast", id: "io.github.jaman.beast", orientation: :landscape]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:host), do: ["lib"]
  defp elixirc_paths(_mobile), do: ["lib/beast"]

  defp deps do
    [
      {:cauldron_2d, path: "../../../cauldron_2d"},
      {:cauldron_2d_net, path: "../../../cauldron_2d_net"},
      {:cauldron_2d_drafter, path: "../../../cauldron_2d_drafter", targets: :host},
      {:cauldron_2d_wx, path: "../../../cauldron_2d_wx", targets: :host},
      {:cauldron_2d_native, path: "../../../cauldron_2d_native", targets: @mobile},
      {:cauldron_native, path: "../../../cauldron_native", runtime: Mix.target() in @mobile},
      {:cauldron_2d_assets,
       path: "../../../cauldron_2d_assets", only: :dev, runtime: false, targets: :host},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
