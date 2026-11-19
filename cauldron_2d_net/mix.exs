defmodule Cauldron2D.Net.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/jaman/cauldron"
  @description "A Cauldron2D world over the network: its scenes sent as pictures or scene data (a Cauldron.Net drawer), the browser pages that draw them, and a server for a game in one line."

  def project do
    [
      app: :cauldron_2d_net,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      test_ignore_filters: [&String.starts_with?(&1, "test/js/")],
      deps: deps(),
      name: "Cauldron2D.Net",
      source_url: @source_url,
      package: package(),
      plumb: [readme: :exact],
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:cauldron_core, "~> 0.4.0", "../cauldron_core", []),
      family(:cauldron_net, "~> 0.4.0", "../cauldron_net", []),
      family(:cauldron_2d, "~> 0.4.0", "../cauldron_2d", []),
      family(:french_curve, "~> 0.2.2", "../../french_curve", override: true),
      family(:gamepad, "~> 0.1.1", "../../gamepad", []),
      family(:tuning_fork, "~> 0.1.15", "../../tuning_fork/tuning_fork", []),
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.13"},
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
      files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE COMMERCIAL.md guides)
    ]
  end

  defp docs do
    [
      main: "readme",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_2d_net/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
