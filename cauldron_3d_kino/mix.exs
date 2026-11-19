defmodule Cauldron3D.Kino.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/jaman/cauldron"
  @description "3D scenes in Livebook: a Kino cell drawing cauldron_gpu's change stream with three.js on the viewer's graphics card."

  def project do
    [
      app: :cauldron_3d_kino,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron3D.Kino",
      source_url: @source_url,
      package: package(),
      plumb: [readme: :exact],
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      family(:cauldron_3d_scene, "~> 0.4.0", "../cauldron_3d_scene", []),
      family(:cauldron_3d_net, "~> 0.4.0", "../cauldron_3d_net", []),
      {:kino, "~> 0.12"},
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
      licenses: ["AGPL-3.0-only"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib notebooks mix.exs README.md CHANGELOG.md LICENSE COMMERCIAL.md guides)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_3d_kino/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md", "notebooks/scene.livemd"]
    ]
  end
end
