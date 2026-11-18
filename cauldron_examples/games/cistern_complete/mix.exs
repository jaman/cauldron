defmodule CisternComplete.MixProject do
  use Mix.Project

  def project do
    [
      app: :cistern_complete,
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
      {:cauldron_2d, path: "../../../cauldron_2d"},
      {:cauldron_2d_drafter, path: "../../../cauldron_2d_drafter"},
      {:cauldron_2d_net, path: "../../../cauldron_2d_net"},
      {:cauldron_2d_assets, path: "../../../cauldron_2d_assets", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
