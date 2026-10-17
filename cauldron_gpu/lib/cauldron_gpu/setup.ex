defmodule CauldronGPU.Setup do
  @moduledoc """
  What building the renderer needs on this machine, and the build configuration
  `mix cauldron_gpu.setup` writes.

  Each platform module (`CauldronGPU.Setup.MacOS`, `CauldronGPU.Setup.Linux`,
  `CauldronGPU.Setup.Windows`) implements `CauldronGPU.Setup.Platform`: it looks for each
  thing the build needs in that platform's usual places, installs what it can, and turns
  what it found into configuration.

  The configuration is `build.config` in `:filename.basedir(:user_config, "cauldron_gpu")`,
  Erlang terms read with `:file.consult/1`. `mix.exs` passes it to `make` or `nmake`:

    * `{choice, card | software}`: `software` builds no renderer
    * `{pkg_config, Path}`: `PKG_CONFIG`, the `pkg-config` program
    * `{pkg_config_path, Path}`: added to `PKG_CONFIG_PATH`
    * `{sdl3_dir, Path}`: `SDL3_DIR`, an SDL3 development folder (Windows)
    * `{vulkan_include, Path}`: `VULKAN_INCLUDE`, the folder holding `vulkan/vulkan.hpp`
    * `{msvc_env, [{Name, Value}]}`: the environment MSVC's `vcvars64.bat` sets, used when
      `cl` is not already on `PATH`
    * `{nmake, Path}`: MSVC's `nmake.exe`, used when `nmake` is not on `PATH`

  Other variables already set in the environment take precedence over the file.
  """

  @sdl3_version "3.4.18"
  @vulkan_headers_version "1.4.350"

  @typedoc """
  One thing the build needs:

    * `key`: the platform's name for it
    * `name`: what to call it when talking to a person
    * `required?`: whether the renderer can be built without it
    * `found`: where it is, or `nil`
    * `install`: what the automatic install does, or `nil` when it cannot be automated
    * `manual`: how a person installs it themselves
  """
  @type item :: %{
          key: atom(),
          name: String.t(),
          required?: boolean(),
          found: String.t() | nil,
          install: String.t() | nil,
          manual: String.t()
        }

  @doc "The platform module for the machine this runs on."
  @spec platform() :: module()
  def platform do
    case :os.type() do
      {:unix, :darwin} -> CauldronGPU.Setup.MacOS
      {:win32, _} -> CauldronGPU.Setup.Windows
      {:unix, _} -> CauldronGPU.Setup.Linux
    end
  end

  @doc "The SDL3 release downloaded when SDL3 is fetched rather than installed."
  @spec sdl3_version() :: String.t()
  def sdl3_version, do: @sdl3_version

  @doc "The Vulkan-Headers release downloaded when Vulkan's headers are missing."
  @spec vulkan_headers_version() :: String.t()
  def vulkan_headers_version, do: @vulkan_headers_version

  @doc "The folder downloads and builds go into."
  @spec cache_dir() :: Path.t()
  def cache_dir, do: :filename.basedir(:user_cache, "cauldron_gpu") |> to_string()

  @doc "The configuration file's path."
  @spec config_path() :: Path.t()
  def config_path,
    do: Path.join(to_string(:filename.basedir(:user_config, "cauldron_gpu")), "build.config")

  @doc "The configuration written last, or `%{}`."
  @spec read_config() :: map()
  def read_config do
    case :file.consult(config_path()) do
      {:ok, terms} -> Map.new(terms)
      {:error, _reason} -> %{}
    end
  end

  @doc "Writes `config` as the configuration, replacing the file."
  @spec write_config(map()) :: :ok
  def write_config(config) do
    File.mkdir_p!(Path.dirname(config_path()))
    terms = for {key, value} <- Enum.sort(config), do: :io_lib.format(~c"~p.~n", [{key, value}])
    File.write!(config_path(), terms)
  end

  @doc """
  The environment variables `config` sets for the build, as `mix.exs` passes them; set in
  this process before rebuilding, so the build that follows uses them.
  """
  @spec build_env(map()) :: [{String.t(), String.t()}]
  def build_env(config) do
    msvc = Enum.map(Map.get(config, :msvc_env, []), fn {name, value} -> {name, value} end)

    pkg_config =
      case config[:pkg_config_path] do
        nil -> []
        path -> [{"PKG_CONFIG_PATH", path <> path_separator(System.get_env("PKG_CONFIG_PATH"))}]
      end

    [
      {"CAULDRON_GPU_SKIP", if(config[:choice] == :software, do: "1")},
      {"SDL3_DIR", config[:sdl3_dir]},
      {"PKG_CONFIG", config[:pkg_config]},
      {"VULKAN_INCLUDE", config[:vulkan_include]}
    ]
    |> Enum.reject(fn {_name, value} -> value == nil end)
    |> Kernel.++(pkg_config ++ msvc)
    |> Enum.map(fn {name, value} -> {to_string(name), to_string(value)} end)
  end

  @doc """
  Whether games can draw on the graphics card: `{:ok, device, backends}` when the renderer
  loads and opens an offscreen device, else `{:error, text}` saying why. Loads the
  renderer again first, so a build made since this process started is the one checked.
  """
  @spec card_status() :: {:ok, String.t(), [atom()]} | {:error, String.t()}
  def card_status do
    native = CauldronGPU.Native
    :persistent_term.erase({native, :error})
    :code.delete(native)
    :code.purge(native)

    with {:module, ^native} <- Code.ensure_loaded(native),
         [_ | _] = backends <- CauldronGPU.backends() do
      opened(backends)
    else
      {:error, _reason} -> {:error, "cauldron_gpu is not compiled"}
      [] -> {:error, "the renderer is not built: #{native.load_error() || "no backend"}"}
    end
  end

  defp opened(backends) do
    case CauldronGPU.Host.open(window: false, width: 16, height: 16) do
      {:ok, host} ->
        CauldronGPU.Host.close(host)
        {:ok, host.info.device, backends}

      {:error, reason} ->
        {:error, "the renderer could not open the graphics card: #{reason}"}
    end
  end

  defp path_separator(nil), do: ""
  defp path_separator(""), do: ""
  defp path_separator(existing), do: ":" <> existing
end
