defmodule Web3D.MixProject do
  use Mix.Project

  def project do
    [
      app: :web_3d,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:cauldron_3d_net, path: "../../../cauldron_3d_net"},
      {:bandit, "~> 1.5"}
    ]
  end
end
