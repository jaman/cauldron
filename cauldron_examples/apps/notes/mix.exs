defmodule Notes.MixProject do
  use Mix.Project

  def project do
    [
      app: :notes,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [notes: [include_erts: false, strip_beams: true]],
      cauldron_native: [name: "Notes", id: "io.github.jaman.notes", orientation: :any]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:cauldron_native, path: "../../../cauldron_native"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
