defmodule Cauldron2D.Easel.Kino.MixProject do
  use Mix.Project

  @version "0.3.2"
  @source_url "https://github.com/jaman/cauldron"
  @description "Cauldron2D art in Livebook: pictures, sheets and animations as Kino images."

  def project do
    [
      app: :cauldron_2d_easel_kino,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron2D.Easel.Kino",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:cauldron_2d, "~> 0.3.2", "../cauldron_2d", []),
      family(:cauldron_2d_easel, "~> 0.3.2", "../cauldron_2d_easel", []),
      family(:linocut, "~> 0.3.2", "../linocut", []),
      family(:french_curve, "~> 0.2.1", "../../french_curve", override: true),
      {:kino, "~> 0.12"}
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
      files: ~w(lib notebooks mix.exs README.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern:
        "#{@source_url}/blob/v#{@version}/cauldron_2d_easel_kino/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
