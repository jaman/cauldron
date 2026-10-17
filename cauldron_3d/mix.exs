defmodule Cauldron3D.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/jaman/cauldron"
  @description "A 3D software renderer and collision for terminals, in Elixir: cameras, polygons, meshes, BSP worlds and hull tracing."

  def project do
    [
      app: :cauldron_3d,
      version: @version,
      elixir: "~> 1.18",
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      make_env: %{"PRIV_DIR" => "priv/native/#{:erlang.system_info(:system_architecture)}"},
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "Cauldron3D",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application, do: [extra_applications: []]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.9", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
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
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_3d/%{path}#L%{line}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
