defmodule Cauldron2D.MixProject do
  use Mix.Project

  @version "0.3.4"
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
    [extra_applications: [:xmerl], mod: {Cauldron2D.Application, []}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.9", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:cauldron_core, "~> 0.4.0", "../cauldron_core", []),
      family(:french_curve, "~> 0.2.1", "../../french_curve", override: true),
      family(:linocut, "~> 0.3.4", "../linocut", [])
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
      files:
        ~w(lib c_src Makefile Makefile.win mix.exs README.md CHANGELOG.md LICENSE COMMERCIAL.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_2d/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md", "guides/tutorial.md"],
      groups_for_modules: [
        Clients: [~r/^Cauldron2D\.Client\./],
        Pictures: [
          Cauldron2D.Picture,
          Cauldron2D.Shapes,
          Cauldron2D.Raster,
          Cauldron2D.Font,
          Cauldron2D.Palette
        ],
        Drawing: [
          ~r/^Cauldron2D\.Atlas/,
          Cauldron2D.Surface,
          ~r/^Cauldron2D\.Camera/,
          Cauldron2D.Renderer,
          Cauldron2D.Draw,
          Cauldron2D.DrawList,
          Cauldron2D.Render,
          Cauldron2D.Blend,
          ~r/^Cauldron2D\.Projection/,
          ~r/^Cauldron2D\.Parallax/,
          Cauldron2D.Screen,
          Cauldron2D.Menu.Layout,
          Cauldron2D.Sheet,
          Cauldron2D.Minimap,
          Cauldron2D.Fit
        ],
        "Movement and collision": [
          Cauldron2D.Body,
          ~r/^Cauldron2D\.Collision/,
          Cauldron2D.Box,
          Cauldron2D.BoxBody,
          Cauldron2D.Jump,
          Cauldron2D.Walk,
          ~r/^Cauldron2D\.Projectiles/,
          Cauldron2D.Steering,
          Cauldron2D.Shape,
          Cauldron2D.Mask,
          Cauldron2D.Overlap,
          Cauldron2D.Turn,
          ~r/^Cauldron2D\.Particles/,
          ~r/^Cauldron2D\.Grid/,
          Cauldron2D.Route,
          Cauldron2D.Steer
        ],
        Sectors: [~r/^Cauldron2D\.Sectors/],
        Maps: [~r/^Cauldron2D\.Map/]
      ]
    ]
  end
end
