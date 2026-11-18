defmodule GpuShowcase.MixProject do
  use Mix.Project

  @mobile [:ios, :android]

  def project do
    [
      app: :gpu_showcase,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.target()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        gpu_showcase: [
          include_executables_for: [:unix],
          include_erts: Mix.target() == :host,
          steps: steps(Mix.target())
        ]
      ],
      cauldron_native: [
        name: "GPU Showcase",
        id: "io.github.jaman.gpushowcase",
        orientation: :landscape
      ]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {GpuShowcase.Application, []}]
  end

  defp elixirc_paths(:host), do: ["lib"]
  defp elixirc_paths(_mobile), do: ["lib", "lib_mobile"]

  defp steps(:host), do: [:assemble, :tar]
  defp steps(_mobile), do: [:assemble]

  defp deps do
    [
      {:cauldron_gpu, path: "../../../cauldron_gpu"},
      {:cauldron_native, path: "../../../cauldron_native", runtime: Mix.target() in @mobile},
    ]
  end
end
