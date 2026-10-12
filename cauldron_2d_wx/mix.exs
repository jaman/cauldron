defmodule Cauldron2D.Wx.MixProject do
  use Mix.Project

  @version "0.2.3"
  @source_url "https://github.com/jaman/cauldron"
  @description "A Cauldron2D game in a wx window: the desktop front end."

  def project do
    [
      app: :cauldron_2d_wx,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron2D.Wx",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :wx, :inets, :ssl]]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:cauldron_2d, "~> 0.2.3", "../cauldron_2d", []),
      family(:cauldron_2d_net, "~> 0.2.3", "../cauldron_2d_net", []),
      family(:french_curve, "~> 0.2.0", "../../french_curve", override: true),
      family(:tuning_fork, "~> 0.1.13", "../../tuning_fork/tuning_fork", []),
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
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_2d_wx/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
