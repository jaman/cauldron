defmodule Cauldron3D.Scene.MixProject do
  use Mix.Project

  @version "0.3.4"
  @source_url "https://github.com/jaman/cauldron"
  @description "A 3D scene as plain Elixir, drawn by any renderer that implements its Target protocol: meshes, materials, lights, cameras, 2D layers, the change stream and the Quake, Doom and Half-Life converters."

  def project do
    [
      app: :cauldron_3d_scene,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      consolidate_protocols: false,
      deps: deps(),
      name: "Cauldron3D.Scene",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      family(:cauldron_core, "~> 0.4.0", "../cauldron_core", optional: true),
      family(:cauldron_2d, "~> 0.4.0", "../cauldron_2d", optional: true),
      family(:cauldron_3d, "~> 0.4.0", "../cauldron_3d", optional: true),
      family(:cauldron_3d_formats, "~> 0.4.0", "../cauldron_3d_formats", optional: true),
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
      files:
        ~w(lib mix.exs README.md CHANGELOG.md LICENSE COMMERCIAL.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_3d_scene/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
