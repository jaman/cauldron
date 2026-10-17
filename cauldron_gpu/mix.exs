defmodule CauldronGPU.MixProject do
  use Mix.Project

  @version "0.3.3"
  @source_url "https://github.com/jaman/cauldron"
  @description "3D rendering on the graphics card for the BEAM: Metal on macOS, Vulkan on Linux and Windows, driven by a scene described from Elixir."

  def project do
    setup = setup_config()

    [
      app: :cauldron_gpu,
      version: @version,
      elixir: "~> 1.18",
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["clean"],
      make_env: make_env(setup),
      description: @description,
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "CauldronGPU",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ] ++ make_executable(setup)
  end

  defp setup_config do
    path = Path.join(:filename.basedir(:user_config, "cauldron_gpu"), "build.config")

    case :file.consult(path) do
      {:ok, terms} -> Map.new(terms)
      {:error, _reason} -> %{}
    end
  end

  defp make_env(setup) do
    chosen = [
      {"CAULDRON_GPU_SKIP", if(setup[:choice] == :software, do: "1")},
      {"SDL3_DIR", setup[:sdl3_dir]},
      {"PKG_CONFIG", setup[:pkg_config]},
      {"VULKAN_INCLUDE", setup[:vulkan_include]}
    ]

    for {name, value} <- chosen,
        value != nil,
        System.get_env(name) == nil,
        into: msvc_env(setup),
        do: {name, to_string(value)}
  end

  defp msvc_env(setup) do
    base = %{
      "PRIV_DIR" => "priv/native/#{:erlang.system_info(:system_architecture)}",
      "PKG_CONFIG_PATH" => pkg_config_path(setup[:pkg_config_path])
    }

    if System.find_executable("cl"),
      do: base,
      else:
        Enum.into(Map.get(setup, :msvc_env, []), base, fn {name, value} ->
          {to_string(name), to_string(value)}
        end)
  end

  defp pkg_config_path(nil), do: System.get_env("PKG_CONFIG_PATH", "")

  defp pkg_config_path(path) do
    [to_string(path), System.get_env("PKG_CONFIG_PATH")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(":")
  end

  defp make_executable(%{nmake: nmake}) do
    if System.find_executable("nmake"), do: [], else: [make_executable: to_string(nmake)]
  end

  defp make_executable(_setup), do: []

  def application,
    do: [extra_applications: [inets: :optional, ssl: :optional, public_key: :optional]]

  defp deps do
    [
      family(:cauldron_2d, "~> 0.3.3", "../cauldron_2d", optional: true),
      family(:cauldron_3d, "~> 0.3.3", "../cauldron_3d", optional: true),
      family(:cauldron_3d_formats, "~> 0.3.3", "../cauldron_3d_formats", optional: true),
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
