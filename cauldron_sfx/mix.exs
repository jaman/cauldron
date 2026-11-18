defmodule CauldronSFX.MixProject do
  use Mix.Project

  @version "0.3.4"
  @source_url "https://github.com/jaman/cauldron"

  def project do
    [
      app: :cauldron_sfx,
      version: @version,
      elixir: "~> 1.19",
      elixirc_options: [warnings_as_errors: true],
      description:
        "A terminal editor for a game's sound effects: a Cauldron.SFX bank, played and changed as you hear it.",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "CauldronSFX",
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      family(:cauldron_core, "~> 0.4.0", "../cauldron_core", []),
      family(:drafter, "~> 0.5.8", "../../drafter", []),
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
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
      files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE COMMERCIAL.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_sfx/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
