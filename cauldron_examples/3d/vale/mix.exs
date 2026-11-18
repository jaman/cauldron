defmodule Vale.MixProject do
  use Mix.Project

  def project do
    [
      app: :vale,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:cauldron_core, path: "../../../cauldron_core"},
      {:cauldron_2d, path: "../../../cauldron_2d"},
      {:cauldron_2d_drafter, path: "../../../cauldron_2d_drafter"},
      {:cauldron_3d, path: "../../../cauldron_3d"},
      {:cauldron_3d_scene, path: "../../../cauldron_3d_scene"},
      {:cauldron_3d_formats, path: "../../../cauldron_3d_formats"},
      {:cauldron_gpu, path: "../../../cauldron_gpu"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
