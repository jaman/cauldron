defmodule CauldronGPU.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/jaman/cauldron"
  @description "3D rendering on the graphics card for the BEAM: Metal on macOS, Vulkan on Linux and Windows, driven by a scene described from Elixir."

  def project do
    [
      app: :cauldron_gpu,
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
      name: "CauldronGPU",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application, do: [extra_applications: []]

  defp deps do
    [
      family(:cauldron_2d, "~> 0.3.0", "../cauldron_2d", optional: true),
      family(:cauldron_3d, "~> 0.3.0", "../cauldron_3d", optional: true),
      family(:cauldron_3d_formats, "~> 0.3.0", "../cauldron_3d_formats", optional: true),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.9", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp family(app, requirement, path, opts) do
    if System.get_env("PLUMB_HEX") == nil and File.dir?(Path.expand(path, __DIR__)),
      do: {app, [path: path] ++ opts},
      else: {app, requirement, opts}
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib c_src shaders priv/shaders Makefile Makefile.win mix.exs README.md STATE.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_gpu/%{path}#L%{line}",
      extras: ["README.md"]
    ]
  end
end
