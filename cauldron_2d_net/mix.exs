defmodule Cauldron2D.Net.MixProject do
  use Mix.Project

  @version "0.1.4"
  @source_url "https://github.com/jaman/cauldron"
  @description "A Cauldron2D world over the network: served to browsers, desktops and terminals over a WebSocket or from node to node, and the links a client joins it by."

  def project do
    [
      app: :cauldron_2d_net,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron2D.Net",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl], mod: {Cauldron2D.Net.Application, []}]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:cauldron_2d, "~> 0.1.4", "../cauldron_2d", []),
      family(:french_curve, "~> 0.1.4", "../../french_curve", override: true),
      family(:tuning_fork, "~> 0.1.11", "../../tuning_fork/tuning_fork", []),
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
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_2d_net/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
