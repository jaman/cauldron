defmodule CauldronGPU.Setup.Linux do
  @moduledoc """
  Building the renderer on Linux (`CauldronGPU.Setup.Platform`): a C++ compiler, `make` and
  `pkg-config`, SDL3, Vulkan's headers, and a Vulkan driver to run it.

  Looks in `pkg-config`'s search, `/usr/include`, `$VULKAN_SDK/include`, LunarG's SDK
  (`~/vulkan/<version>/x86_64`) and the setup's own folder. Installs through the
  distribution's package manager (apt, dnf, pacman or zypper, run with `sudo`). Vulkan's
  headers are downloaded instead, which needs no administrator rights; the renderer loads
  the driver's Vulkan library when it runs. SDL3 is built from source into the setup's
  folder where the distribution has no SDL3 package.
  """

  @behaviour CauldronGPU.Setup.Platform

  alias CauldronGPU.Setup
  alias CauldronGPU.Setup.{Command, Fetch}

  @managers [
    apt: %{
      program: "apt-get",
      install: ["install", "-y"],
      tools: ~w(build-essential pkg-config),
      sdl3: ~w(libsdl3-dev),
      driver: ~w(libvulkan1 mesa-vulkan-drivers),
      sdl3_build:
        ~w(cmake libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxfixes-dev libxkbcommon-dev libwayland-dev wayland-protocols libegl-dev libdrm-dev libgbm-dev libpulse-dev)
    },
    dnf: %{
      program: "dnf",
      install: ["install", "-y"],
      tools: ~w(gcc-c++ make pkgconf-pkg-config),
      sdl3: ~w(SDL3-devel),
      driver: ~w(vulkan-loader mesa-vulkan-drivers),
      sdl3_build:
        ~w(cmake libX11-devel libXext-devel libXrandr-devel libXcursor-devel libXi-devel libXfixes-devel libxkbcommon-devel wayland-devel wayland-protocols-devel mesa-libEGL-devel libdrm-devel mesa-libgbm-devel pulseaudio-libs-devel)
    },
    pacman: %{
      program: "pacman",
      install: ["-S", "--needed", "--noconfirm"],
      tools: ~w(base-devel pkgconf),
      sdl3: ~w(sdl3),
      driver: ~w(vulkan-icd-loader),
      sdl3_build:
        ~w(cmake libx11 libxext libxrandr libxcursor libxi libxfixes libxkbcommon wayland)
    },
    zypper: %{
      program: "zypper",
      install: ["--non-interactive", "install"],
      tools: ~w(gcc-c++ make pkg-config),
      sdl3: ~w(SDL3-devel),
      driver: ~w(libvulkan1 libvulkan_radeon libvulkan_intel),
      sdl3_build:
        ~w(cmake libX11-devel libXext-devel libXrandr-devel libXcursor-devel libXi-devel libXfixes-devel libxkbcommon-devel wayland-devel wayland-protocols-devel Mesa-libEGL-devel libdrm-devel libgbm-devel libpulse-devel)
    }
  ]

  @icd_dirs ["/usr/share/vulkan/icd.d", "/etc/vulkan/icd.d", "/usr/local/share/vulkan/icd.d"]

  @impl true
  def probe do
    manager = manager()

    [
      %{
        key: :tools,
        name: "a C++ compiler, make and pkg-config",
        required?: true,
        found: tools(),
        install: package_text(manager, :tools),
        manual: "Install a C++20 compiler (g++ 11 or clang 14 or newer), make and pkg-config."
      },
      %{
        key: :sdl3,
        name: "SDL3",
        required?: true,
        found: sdl3(),
        install: sdl3_install_text(manager),
        manual: "Install SDL3's development package, or build SDL3 from libsdl.org."
      },
      %{
        key: :vulkan,
        name: "Vulkan's headers",
        required?: true,
        found: vulkan_include(),
        install:
          "download Vulkan-Headers #{Setup.vulkan_headers_version()} (no administrator rights)",
        manual: "Install Vulkan's development headers, or LunarG's Vulkan SDK."
      },
      %{
        key: :driver,
        name: "a Vulkan driver",
        required?: true,
        found: driver(),
        install: package_text(manager, :driver),
        manual:
          "Install your graphics card's Vulkan driver: Mesa's for AMD and Intel, or NVIDIA's own driver."
      }
    ]
  end

  @impl true
  def install(%{key: :tools}), do: install_packages(:tools)
  def install(%{key: :driver}), do: install_packages(:driver)

  def install(%{key: :vulkan}) do
    version = Setup.vulkan_headers_version()

    Fetch.unpack(
      "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v#{version}.tar.gz",
      :tar_gz,
      Path.join(Setup.cache_dir(), "vulkan-headers")
    )
  end

  def install(%{key: :sdl3}) do
    case manager() do
      {name, manager} -> install_sdl3(name, manager)
      nil -> build_sdl3()
    end
  end

  @impl true
  def config(items) do
    found = Map.new(items, &{&1.key, &1.found})

    %{pkg_config_path: sdl3_pc_dir(found[:sdl3]), vulkan_include: found[:vulkan]}
    |> Enum.reject(fn {_key, value} -> value == nil end)
    |> Map.new()
  end

  defp install_sdl3(name, manager) do
    if available?(name, manager, hd(manager.sdl3)),
      do: install_packages(:sdl3),
      else: with(:ok <- install_packages(:sdl3_build), do: build_sdl3())
  end

  defp build_sdl3 do
    version = Setup.sdl3_version()
    source = Path.join(Setup.cache_dir(), "sdl3-source")
    prefix = Path.join(Setup.cache_dir(), "sdl3")
    tree = Path.join(source, "SDL3-#{version}")
    build = Path.join(tree, "build")

    url =
      "https://github.com/libsdl-org/SDL/releases/download/release-#{version}/SDL3-#{version}.tar.gz"

    with :ok <- Fetch.unpack(url, :tar_gz, source),
         :ok <-
           Command.interactive("cmake", [
             "-S",
             tree,
             "-B",
             build,
             "-DCMAKE_BUILD_TYPE=Release",
             "-DCMAKE_INSTALL_PREFIX=#{prefix}",
             "-DCMAKE_INSTALL_LIBDIR=lib",
             "-DSDL_TESTS=OFF"
           ]),
         :ok <- Command.interactive("cmake", ["--build", build, "--parallel"]),
         do: Command.interactive("cmake", ["--install", build])
  end

  defp tools do
    compiler = Enum.find(["c++", "g++", "clang++"], &System.find_executable/1)

    if compiler && System.find_executable("make") && System.find_executable("pkg-config"),
      do: "#{System.find_executable(compiler)}, make, pkg-config"
  end

  defp sdl3 do
    case Command.output("pkg-config", ["--variable=pcfiledir", "sdl3"]) do
      {:ok, dir} ->
        dir |> String.trim() |> Path.expand()

      :error ->
        dir = Path.join(Setup.cache_dir(), "sdl3/lib/pkgconfig")
        if File.exists?(Path.join(dir, "sdl3.pc")), do: dir
    end
  end

  defp sdl3_pc_dir(nil), do: nil

  defp sdl3_pc_dir(dir) do
    if String.starts_with?(dir, Setup.cache_dir()), do: dir
  end

  defp vulkan_include do
    pkg_config =
      case Command.output("pkg-config", ["--variable=includedir", "vulkan"]) do
        {:ok, dir} -> [String.trim(dir)]
        :error -> []
      end

    sdk = System.get_env("VULKAN_SDK")

    (pkg_config ++
       [
         "/usr/include",
         sdk && Path.join(sdk, "include"),
         Path.join(
           Setup.cache_dir(),
           "vulkan-headers/Vulkan-Headers-#{Setup.vulkan_headers_version()}/include"
         )
       ] ++
       (Path.wildcard(Path.expand("~/vulkan/*/x86_64/include")) |> Enum.sort(:desc)))
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&File.exists?(Path.join(&1, "vulkan/vulkan.hpp")))
  end

  defp driver do
    loader =
      case Command.output("ldconfig", ["-p"]) do
        {:ok, text} ->
          String.contains?(text, "libvulkan.so.1")

        :error ->
          Enum.any?(["/usr/lib", "/usr/lib64"], &File.exists?(Path.join(&1, "libvulkan.so.1")))
      end

    icds = Enum.flat_map(@icd_dirs, &Path.wildcard(Path.join(&1, "*.json")))
    if loader and icds != [], do: Enum.map_join(icds, ", ", &Path.basename/1)
  end

  defp manager do
    Enum.find(@managers, fn {_name, manager} -> System.find_executable(manager.program) end)
  end

  defp package_text(nil, _group), do: nil

  defp package_text({_name, manager}, group),
    do: Enum.join(["sudo", manager.program | manager.install] ++ Map.fetch!(manager, group), " ")

  defp sdl3_install_text(nil),
    do: "build SDL3 #{Setup.sdl3_version()} from source (needs cmake and X11 or Wayland headers)"

  defp sdl3_install_text({name, manager}) do
    if available?(name, manager, hd(manager.sdl3)),
      do: package_text({name, manager}, :sdl3),
      else:
        package_text({name, manager}, :sdl3_build) <>
          ", then build SDL3 #{Setup.sdl3_version()} from source"
  end

  defp install_packages(group) do
    case manager() do
      nil ->
        {:error, "no package manager this setup knows (apt, dnf, pacman or zypper) was found"}

      {_name, manager} ->
        Command.interactive(
          "sudo",
          [manager.program | manager.install] ++ Map.fetch!(manager, group)
        )
    end
  end

  defp available?(:apt, _manager, package), do: Command.succeeds?("apt-cache", ["show", package])
  defp available?(:dnf, _manager, package), do: Command.succeeds?("dnf", ["info", "-q", package])
  defp available?(:pacman, _manager, package), do: Command.succeeds?("pacman", ["-Si", package])

  defp available?(:zypper, _manager, package),
    do: Command.succeeds?("zypper", ["--non-interactive", "search", "--match-exact", package])
end
