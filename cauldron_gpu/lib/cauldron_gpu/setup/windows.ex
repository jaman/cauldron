defmodule CauldronGPU.Setup.Windows do
  @moduledoc """
  Building the renderer on Windows (`CauldronGPU.Setup.Platform`): MSVC's C++ tools, SDL3's
  development files, Vulkan's headers, and a Vulkan driver to run it.

  MSVC is found with Microsoft's `vswhere.exe`, and the environment its `vcvars64.bat` sets
  is kept in the configuration, so builds work from any command prompt. SDL3 is looked for
  in `SDL3_DIR`, the setup's folder, `C:\\SDL3*` and the Downloads folder; Vulkan's headers
  in `VULKAN_INCLUDE`, `VULKAN_SDK`, `C:\\VulkanSDK\\<version>` and the setup's folder. SDL3
  and the headers are downloaded into the setup's folder when missing, which needs no
  administrator rights; the renderer loads the driver's `vulkan-1.dll` when it runs.
  MSVC's Build Tools are installed with `winget`, which asks for administrator rights.
  """

  @behaviour CauldronGPU.Setup.Platform

  alias CauldronGPU.Setup
  alias CauldronGPU.Setup.{Command, Fetch}

  @build_tools_override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

  @impl true
  def probe do
    [
      %{
        key: :msvc,
        name: "Microsoft's C++ Build Tools (MSVC)",
        required?: true,
        found: vcvars(),
        install:
          System.find_executable("winget") &&
            "winget install Microsoft.VisualStudio.2022.BuildTools (asks for administrator rights)",
        manual:
          "Install Visual Studio Build Tools with the \"Desktop development with C++\" workload from https://visualstudio.microsoft.com/visual-cpp-build-tools/."
      },
      %{
        key: :sdl3,
        name: "SDL3's development files",
        required?: true,
        found: sdl3_dir(),
        install: "download SDL3 #{Setup.sdl3_version()} (no administrator rights)",
        manual:
          "Download SDL3-devel-#{Setup.sdl3_version()}-VC.zip from https://github.com/libsdl-org/SDL/releases and unzip it."
      },
      %{
        key: :vulkan,
        name: "Vulkan's headers",
        required?: true,
        found: vulkan_include(),
        install:
          "download Vulkan-Headers #{Setup.vulkan_headers_version()} (no administrator rights)",
        manual: "Install LunarG's Vulkan SDK from https://vulkan.lunarg.com."
      },
      %{
        key: :driver,
        name: "a Vulkan driver",
        required?: true,
        found: driver(),
        install: nil,
        manual:
          "Install your graphics card's driver from AMD, Intel or NVIDIA; it includes Vulkan."
      }
    ]
  end

  @impl true
  def install(%{key: :msvc}) do
    Command.interactive("winget", [
      "install",
      "--id",
      "Microsoft.VisualStudio.2022.BuildTools",
      "-e",
      "--accept-package-agreements",
      "--accept-source-agreements",
      "--override",
      @build_tools_override
    ])
  end

  def install(%{key: :sdl3}) do
    version = Setup.sdl3_version()

    Fetch.unpack(
      "https://github.com/libsdl-org/SDL/releases/download/release-#{version}/SDL3-devel-#{version}-VC.zip",
      :zip,
      Path.join(Setup.cache_dir(), "sdl3")
    )
  end

  def install(%{key: :vulkan}) do
    version = Setup.vulkan_headers_version()

    Fetch.unpack(
      "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v#{version}.zip",
      :zip,
      Path.join(Setup.cache_dir(), "vulkan-headers")
    )
  end

  def install(%{key: :driver}), do: {:error, "a driver is installed from the card maker's site"}

  @impl true
  def config(items) do
    found = Map.new(items, &{&1.key, &1.found})
    msvc = msvc_env(found[:msvc])

    %{
      sdl3_dir: backslashed(found[:sdl3]),
      vulkan_include: backslashed(found[:vulkan]),
      msvc_env: msvc,
      nmake: nmake(msvc)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp backslashed(nil), do: nil
  defp backslashed(path), do: String.replace(path, "/", "\\")

  defp vcvars do
    vswhere =
      Path.join([
        System.get_env("ProgramFiles(x86)", "C:\\Program Files (x86)"),
        "Microsoft Visual Studio",
        "Installer",
        "vswhere.exe"
      ])

    args = [
      "-latest",
      "-products",
      "*",
      "-requires",
      "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
      "-property",
      "installationPath"
    ]

    with true <- File.exists?(vswhere),
         {:ok, text} <- Command.output(vswhere, args),
         [install | _rest] <- String.split(text, ["\r\n", "\n"], trim: true),
         bat = Path.join(install, "VC/Auxiliary/Build/vcvars64.bat"),
         true <- File.exists?(bat) do
      bat
    else
      _missing -> nil
    end
  end

  defp msvc_env(nil), do: []

  defp msvc_env(vcvars) do
    script = Path.join(System.tmp_dir!(), "cauldron_gpu_vcvars.bat")
    File.write!(script, "@call \"#{vcvars}\" >nul\r\n@set\r\n")
    {text, _status} = System.cmd("cmd", ["/c", script], stderr_to_stdout: true)
    File.rm(script)

    for line <- String.split(text, ["\r\n", "\n"], trim: true),
        [name, value] <- [String.split(line, "=", parts: 2)],
        String.upcase(name) in ["PATH", "INCLUDE", "LIB", "LIBPATH"],
        do: {String.upcase(name), value}
  end

  defp nmake(msvc) do
    with {_name, path} <- List.keyfind(msvc, "PATH", 0),
         dir when is_binary(dir) <-
           Enum.find(String.split(path, ";"), &File.exists?(Path.join(&1, "nmake.exe"))) do
      Path.join(dir, "nmake.exe")
    else
      _missing -> nil
    end
  end

  defp sdl3_dir do
    home = System.get_env("USERPROFILE", "")

    ([
       System.get_env("SDL3_DIR"),
       Path.join(Setup.cache_dir(), "sdl3/SDL3-#{Setup.sdl3_version()}")
     ] ++
       Enum.sort(Path.wildcard("C:/SDL3*"), :desc) ++
       Enum.sort(Path.wildcard(Path.join(home, "Downloads/SDL3-*")), :desc))
    |> Enum.reject(&is_nil/1)
    |> Enum.find(fn dir ->
      File.exists?(Path.join(dir, "include/SDL3/SDL.h")) and
        File.exists?(Path.join(dir, "lib/x64/SDL3.lib"))
    end)
  end

  defp vulkan_include do
    sdk = System.get_env("VULKAN_SDK")

    ([
       System.get_env("VULKAN_INCLUDE"),
       sdk && Path.join(sdk, "Include"),
       Path.join(
         Setup.cache_dir(),
         "vulkan-headers/Vulkan-Headers-#{Setup.vulkan_headers_version()}/include"
       )
     ] ++ Enum.sort(Path.wildcard("C:/VulkanSDK/*/Include"), :desc))
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.exists?(Path.join(&1, "vulkan/vulkan.hpp")))
  end

  defp driver do
    dll = Path.join(System.get_env("SystemRoot", "C:\\Windows"), "System32/vulkan-1.dll")
    if File.exists?(dll), do: dll
  end
end
