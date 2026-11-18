defmodule Cauldron.MixProject do
  use Mix.Project

  @version "0.3.4"
  @source_url "https://github.com/jaman/cauldron"
  @description "The game engine every Cauldron game runs on: worlds, players, input, menus, sound and saving, with no way of drawing in it."

  def project do
    [
      app: :cauldron_core,
      version: @version,
      elixir: "~> 1.18",
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      name: "Cauldron",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [mod: {Cauldron.Application, []}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      family(:tuning_fork, "~> 0.1.13", "../../tuning_fork/tuning_fork", []),
      family(:tuning_fork_speaker, "~> 0.1.13", "../../tuning_fork/tuning_fork_speaker", [])
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
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_core/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Worlds and players": [
          Cauldron.Game,
          ~r/^Cauldron\.World/,
          ~r/^Cauldron\.Worlds/,
          Cauldron.Player,
          Cauldron.Robot,
          ~r/^Cauldron\.Replay/,
          Cauldron.Sessions,
          Cauldron.Chat,
          Cauldron.Stats,
          Cauldron.Test,
          Cauldron.Distribution,
          Cauldron.Link,
          ~r/^Cauldron\.Beacon/,
          Cauldron.Loop
        ],
        Clients: [~r/^Cauldron\.Client\./, Cauldron.Front, ~r/^Cauldron\.Menu/],
        Input: [~r/^Cauldron\.Input/, Cauldron.Presses],
        "Game state": [
          Cauldron.Rng,
          Cauldron.Timers,
          Cauldron.Tuning,
          Cauldron.Tween,
          Cauldron.Ease,
          Cauldron.States,
          Cauldron.Thinkers,
          Cauldron.Effects,
          Cauldron.Impact,
          Cauldron.Moves
        ],
        "Sound and files": [
          ~r/^Cauldron\.Audio/,
          ~r/^Cauldron\.Ledger/,
          Cauldron.Save,
          Cauldron.Paths,
          Cauldron.Scores,
          Cauldron.Launch,
          Cauldron.Trace
        ]
      ]
    ]
  end
end
