defmodule Cauldron2D.GameMaker.MixProject do
  use Mix.Project

  @version "0.2.6"
  @source_url "https://github.com/jaman/cauldron"
  @description "Reads GameMaker games' data files for Cauldron2D: sprites, texture pages, tilesets, objects and their events, rooms with their layers, sounds, fonts and paths."

  def project do
    [
      app: :cauldron_2d_gamemaker,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron2D.GameMaker",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      family(:cauldron_2d, "~> 0.2.6", "../cauldron_2d", []),
      family(:linocut, "~> 0.2.6", "../linocut", override: true),
      family(:french_curve, "~> 0.2.0", "../../french_curve", override: true),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
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
      files: ~w(lib mix.exs README.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern:
        "#{@source_url}/blob/v#{@version}/cauldron_2d_gamemaker/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
