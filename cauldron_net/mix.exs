defmodule Cauldron.Net.MixProject do
  use Mix.Project

  @version "0.3.4"
  @source_url "https://github.com/jaman/cauldron"
  @description "A Cauldron world over the network: the channel and socket browsers join through, the sessions behind them, and the links an Elixir client joins a world by, with what a frame looks like left to a drawer."

  def project do
    [
      app: :cauldron_net,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron.Net",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl], mod: {Cauldron.Net.Application, []}]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:cauldron_core, "~> 0.4.0", "../cauldron_core", []),
      family(:gamepad, "~> 0.1.0", "../../gamepad", []),
      family(:tuning_fork, "~> 0.1.13", "../../tuning_fork/tuning_fork", []),
      {:phoenix, "~> 1.8"},
      {:mint, "~> 1.6"},
      {:mint_web_socket, "~> 1.0"},
      {:castore, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"}
    ]
  end

  defp family(app, requirement, path, opts) do
    if System.get_env("PLUMB_HEX") == nil and File.dir?(path),
      do: {app, [path: path] ++ opts},
      else: {app, requirement, Keyword.delete(opts, :override)}
  end

  defp package do
    [
      licenses: ["AGPL-3.0-only"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib mix.exs README.md CHANGELOG.md LICENSE COMMERCIAL.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_net/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
