defmodule Cauldron2D.MixProject do
  use Mix.Project

  @version "0.2.3"
  @source_url "https://github.com/jaman/cauldron"
  @description "A 2D tile engine for terminals: a grid of tile ids, cheaply, as pixels or glyphs."

  def project do
    [
      app: :cauldron_2d,
      version: @version,
      elixir: "~> 1.18",
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      make_env: %{"PRIV_DIR" => "priv/native/#{:erlang.system_info(:system_architecture)}"},
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Cauldron2D",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [], mod: {Cauldron2D.Application, []}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.9", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:french_curve, "~> 0.2.0", "../../french_curve", override: true),
      family(:linocut, "~> 0.2.3", "../linocut", []),
      # Synthesis and mixing. Playing the result through a speaker is
      # `tuning_fork_speaker`, which a game adds if it wants to be heard — the engine works
      # without it and stays silent.
      family(:tuning_fork, "~> 0.1.13", "../../tuning_fork/tuning_fork", [])
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
      files: ~w(lib c_src Makefile Makefile.win mix.exs README.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_2d/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md", "guides/tutorial.md"]
    ]
  end
end
