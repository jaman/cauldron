defmodule NowInAndroidServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :now_in_android_server,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application,
    do: [extra_applications: [:logger], mod: {NowInAndroidServer.Application, []}]

  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:plug, "~> 1.18"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
