defmodule CauldronGPU.Setup.MacOS do
  @moduledoc """
  Building the renderer on macOS (`CauldronGPU.Setup.Platform`): Apple's command-line tools
  for Swift and Metal, `pkg-config` and SDL3 from Homebrew, and, for the Vulkan backend
  that runs through MoltenVK, Vulkan's loader and headers.

  Looks in `pkg-config`'s own search, Homebrew (`/opt/homebrew`, `/usr/local`), MacPorts
  (`/opt/local`) and LunarG's SDK (`~/VulkanSDK/<version>/macOS`). Installs through
  Homebrew, and installs Homebrew itself with its official installer when it is missing.
  """

  @behaviour CauldronGPU.Setup.Platform

  alias CauldronGPU.Setup.Command

  @prefixes ["/opt/homebrew", "/usr/local", "/opt/local"]
  @homebrew_installer "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

  @impl true
  def probe do
    brew = brew()

    [
      %{
        key: :command_line_tools,
        name: "Apple's command-line tools (Swift and Metal)",
        required?: true,
        found: command_line_tools(),
        install: "xcode-select --install",
        manual: "Run xcode-select --install and finish the installer it opens."
      },
      %{
        key: :homebrew,
        name: "Homebrew",
        required?: true,
        found: brew,
        install: "Homebrew's installer (asks for your password)",
        manual: "Install Homebrew from https://brew.sh."
      },
      %{
        key: :pkg_config,
        name: "pkg-config",
        required?: true,
        found: pkg_config(),
        install: brew && "brew install pkgconf",
        manual: "Install pkg-config, for example with brew install pkgconf."
      },
      %{
        key: :sdl3,
        name: "SDL3",
        required?: true,
        found: pc_dir("sdl3"),
        install: brew && "brew install sdl3",
        manual: "Install SDL3, for example with brew install sdl3."
      },
      %{
        key: :vulkan,
        name: "Vulkan through MoltenVK (a second backend; Metal is used first)",
        required?: false,
        found: pc_dir("vulkan"),
        install: brew && "brew install vulkan-headers vulkan-loader molten-vk",
        manual: "Install vulkan-headers, vulkan-loader and molten-vk with Homebrew."
      }
    ]
  end

  @impl true
  def install(%{key: :command_line_tools}) do
    with :ok <- Command.interactive("xcode-select", ["--install"]),
         do: {:wait, "Finish the installer macOS opened, then press Enter."}
  end

  def install(%{key: :homebrew}),
    do: Command.interactive("/bin/bash", ["-c", "curl -fsSL #{@homebrew_installer} | bash"])

  def install(%{key: :pkg_config}), do: brew_install(["pkgconf"])
  def install(%{key: :sdl3}), do: brew_install(["sdl3"])

  def install(%{key: :vulkan}),
    do: brew_install(["vulkan-headers", "vulkan-loader", "molten-vk"])

  @impl true
  def config(items) do
    found = Map.new(items, &{&1.key, &1.found})
    program = found[:pkg_config]

    %{
      pkg_config: if(System.find_executable("pkg-config") != program, do: program),
      pkg_config_path:
        if(program && not Command.succeeds?(program, ["--exists", "sdl3"]), do: found[:sdl3])
    }
    |> Enum.reject(fn {_key, value} -> value == nil end)
    |> Map.new()
  end

  defp command_line_tools do
    with {:ok, path} <- Command.output("xcode-select", ["-p"]),
         true <- Command.succeeds?("xcrun", ["--find", "swiftc"]) do
      String.trim(path)
    else
      _missing -> nil
    end
  end

  defp brew do
    Enum.find(
      [System.find_executable("brew") | Enum.map(@prefixes, &Path.join(&1, "bin/brew"))],
      &(&1 && File.exists?(&1))
    )
  end

  defp brew_install(formulae) do
    case brew() do
      nil -> {:error, "Homebrew is not installed"}
      path -> Command.interactive(path, ["install" | formulae])
    end
  end

  defp pkg_config do
    Enum.find(
      [
        System.find_executable("pkg-config")
        | Enum.map(@prefixes, &Path.join(&1, "bin/pkg-config"))
      ],
      &(&1 && File.exists?(&1))
    )
  end

  defp pc_dir(package) do
    with program when is_binary(program) <- pkg_config(),
         {:ok, dir} <- Command.output(program, ["--variable=pcfiledir", package]) do
      dir |> String.trim() |> Path.expand()
    else
      _missing -> Enum.find(pc_dirs(), &File.exists?(Path.join(&1, package <> ".pc")))
    end
  end

  defp pc_dirs do
    sdk = Path.wildcard(Path.expand("~/VulkanSDK/*/macOS/lib/pkgconfig")) |> Enum.sort(:desc)
    Enum.map(@prefixes, &Path.join(&1, "lib/pkgconfig")) ++ sdk
  end
end
