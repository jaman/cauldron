defmodule Cauldron3D.Net.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/jaman/cauldron"
  @description "3D scenes for the browser: a scene server broadcasting cauldron_gpu's change stream over a Phoenix channel, and a three.js client drawing it."

  def project do
    [
      app: :cauldron_3d_net,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron3D.Net",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {Cauldron3D.Net.Application, []}]
  end

  defp deps do
    [
      family(:cauldron_gpu, "~> 0.3.0", "../cauldron_gpu", []),
      family(:cauldron_3d_formats, "~> 0.3.0", "../cauldron_3d_formats", only: [:dev, :test]),
      {:phoenix, "~> 1.8"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.5", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp family(app, requirement, path, opts) do
    if System.get_env("PLUMB_HEX") == nil and File.dir?(Path.expand(path, __DIR__)),
      do: {app, [path: path] ++ opts},
      else: {app, requirement, opts}
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv mix.exs README.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_3d_net/%{path}#L%{line}",
      extras: ["README.md"]
    ]
  end
end
