defmodule Courtyard.MixProject do
  use Mix.Project

  @mobile [:ios, :android]

  def project do
    [
      app: :courtyard,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.target()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [courtyard: [include_erts: false, strip_beams: true]],
      cauldron_native: [
        name: "Courtyard",
        id: "io.github.jaman.courtyard",
        orientation: :landscape,
        files: downloaded(),
        env: %{"CAULDRON_ASSETS" => "$ROOT/assets"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :crypto, :public_key],
      mod: {Courtyard.Application, []}
    ]
  end

  defp elixirc_paths(:host), do: ["lib"]
  defp elixirc_paths(_mobile), do: ["lib/courtyard"]

  defp downloaded do
    root =
      System.get_env("CAULDRON_ASSETS") ||
        Path.join(:filename.basedir(:user_cache, "cauldron"), "assets")

    if File.dir?(root), do: [{root, "assets"}], else: []
  end

  defp deps do
    [
      {:cauldron_2d, path: "../../../cauldron_2d"},
      {:cauldron_2d_drafter, path: "../../../cauldron_2d_drafter", targets: :host},
      {:cauldron_2d_net, path: "../../../cauldron_2d_net"},
      {:cauldron_3d_net, path: "../../../cauldron_3d_net"},
      {:cauldron_2d_native, path: "../../../cauldron_2d_native", targets: @mobile},
      {:cauldron_native, path: "../../../cauldron_native", runtime: Mix.target() in @mobile},
      {:cauldron_gpu, path: "../../../cauldron_gpu"},
      {:cauldron_3d_formats, path: "../../../cauldron_3d_formats"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
