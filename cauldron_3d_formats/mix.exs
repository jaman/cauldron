defmodule Cauldron3D.Formats.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/jaman/cauldron"
  @description "Readers for the Quake family of game files into Cauldron3D: map files, models, sprites, picture collections, sounds, entity text and pak and pk3 archives."

  def project do
    [
      app: :cauldron_3d_formats,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron3D.Formats",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application, do: [extra_applications: [:stdlib]]

  defp deps do
    [
      {:cauldron_3d, path: "../cauldron_3d"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
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
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_3d_formats/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
