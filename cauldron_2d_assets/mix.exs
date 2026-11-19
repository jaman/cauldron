defmodule Cauldron2D.Assets.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/jaman/cauldron"
  @description "A game's art made by image models: asked for, chosen, and finished as pixel art."

  def project do
    [
      app: :cauldron_2d_assets,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron2D.Assets",
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      family(:french_curve, "~> 0.2.2", "../../french_curve", override: true),
      family(:linocut, "~> 0.4.0", "../linocut", [])
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
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE COMMERCIAL.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_2d_assets/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
