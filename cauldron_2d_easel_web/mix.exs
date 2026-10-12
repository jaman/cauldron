defmodule Cauldron2D.Easel.Web.MixProject do
  use Mix.Project

  @version "0.2.3"
  @source_url "https://github.com/jaman/cauldron"
  @description "Edits a Cauldron2D atlas in a browser, with LiveView."

  def project do
    [
      app: :cauldron_2d_easel_web,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Cauldron2D.Easel.Web",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:cauldron_2d, "~> 0.2.3", "../cauldron_2d", []),
      family(:cauldron_2d_easel, "~> 0.2.3", "../cauldron_2d_easel", []),
      family(:linocut, "~> 0.2.3", "../linocut", []),
      family(:french_curve, "~> 0.2.0", "../../french_curve", override: true),
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_html, "~> 4.2"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.12", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test}
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
      source_url_pattern:
        "#{@source_url}/blob/v#{@version}/cauldron_2d_easel_web/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
