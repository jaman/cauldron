defmodule Megablast.MixProject do
  use Mix.Project

  def project do
    [
      app: :megablast,
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
      {:cauldron_2d, path: "../../cauldron_2d"},
      {:cauldron_2d_drafter, path: "../../cauldron_2d_drafter"},
      {:linocut, path: "../../linocut"},
      {:drafter, path: "../../../drafter"},
      {:french_curve, path: "../../../french_curve", override: true},
      {:tuning_fork, path: "../../../tuning_fork/tuning_fork"}
    ]
  end
end
