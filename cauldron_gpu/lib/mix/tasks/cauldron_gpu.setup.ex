defmodule Mix.Tasks.CauldronGpu.Setup do
  @shortdoc "Sets up drawing on the graphics card, or chooses software drawing"

  @moduledoc """
  Finds what building `cauldron_gpu`'s renderer needs on this machine, installs what is
  missing when you agree, builds the renderer, and checks that it opens.

      mix cauldron_gpu.setup
      mix cauldron_gpu.setup --check
      mix cauldron_gpu.setup --software

  Each missing piece is offered as an automatic install, showing what it will run, or as
  steps to follow yourself. Declining leaves games drawing in software, and running the
  task again starts over. The paths found are written to the build configuration
  (`CauldronGPU.Setup`), so later builds use them without environment variables.

  Options:

    * `--check`: report what is found and change nothing
    * `--yes`: accept every automatic install and the build
    * `--software`: build no renderer; games draw in software
  """

  use Mix.Task

  alias CauldronGPU.Setup

  @switches [check: :boolean, yes: :boolean, software: :boolean]

  @impl true
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    platform = Setup.platform()

    cond do
      opts[:software] ->
        choose_software()

      opts[:check] ->
        platform.probe() |> report()

      true ->
        platform.probe() |> report() |> resolve(platform, opts) |> finish(platform, opts)
    end
  end

  defp report(items) do
    Mix.shell().info("\nWhat building the renderer needs:\n")

    Enum.each(items, fn item ->
      status =
        cond do
          item.found -> [:green, "found  ", :reset]
          item.required? -> [:red, "missing", :reset]
          true -> [:yellow, "absent ", :reset]
        end

      where = if item.found, do: [:faint, "  ", item.found, :reset], else: []
      Mix.shell().info(IO.ANSI.format(["  ", status, "  ", item.name | where]))
    end)

    Mix.shell().info("")
    items
  end

  defp resolve(items, platform, opts) do
    missing = Enum.reject(items, & &1.found)

    if missing == [] do
      items
    else
      Enum.each(missing, &offer(&1, platform, opts))
      platform.probe() |> report()
    end
  end

  defp offer(%{install: nil} = item, _platform, _opts) do
    Mix.shell().info("#{item.name} cannot be installed from here. #{item.manual}")
    Mix.shell().prompt("Press Enter once it is installed, or to go on without it.")
  end

  defp offer(item, platform, opts) do
    default = if item.required?, do: :yes, else: :no
    question = "Install #{item.name}? This will #{verb(item.install)}"

    if opts[:yes] || Mix.shell().yes?(question, default: default),
      do: installed(item, platform),
      else: Mix.shell().info("Skipped. #{item.manual}")
  end

  defp verb(install) do
    if String.starts_with?(install, ["download", "build"]),
      do: install <> ".",
      else: "run: " <> install
  end

  defp installed(item, platform) do
    case platform.install(item) do
      :ok ->
        Mix.shell().info("#{item.name}: done.")

      {:wait, text} ->
        Mix.shell().prompt(text)

      {:error, text} ->
        Mix.shell().error("#{item.name} was not installed: #{text}. #{item.manual}")
    end
  end

  defp finish(items, platform, opts) do
    case Enum.filter(items, &(&1.required? and is_nil(&1.found))) do
      [] ->
        if opts[:yes] || Mix.shell().yes?("Build the renderer now?", default: :yes),
          do: build(platform.config(items)),
          else: choose_software()

      missing ->
        names = Enum.map_join(missing, ", ", & &1.name)

        Mix.shell().info(
          "Still missing: #{names}. Games draw in software; run mix cauldron_gpu.setup again once it is installed."
        )
    end
  end

  defp choose_software do
    Setup.write_config(%{choice: :software})

    Mix.shell().info(
      "Games draw in software. Run mix cauldron_gpu.setup to set up the graphics card."
    )

    rebuild(%{choice: :software})
  end

  defp build(config) do
    config = Map.put(config, :choice, :card)
    Setup.write_config(config)
    Mix.shell().info("Wrote #{Setup.config_path()}. Building the renderer...")
    rebuild(config)
    verify()
  end

  defp rebuild(config) do
    System.delete_env("CAULDRON_GPU_SKIP")
    Enum.each(Setup.build_env(config), fn {name, value} -> System.put_env(name, value) end)

    if Mix.Project.config()[:app] == :cauldron_gpu,
      do: mix(["compile.elixir_make"]),
      else: mix(["deps.compile", "cauldron_gpu", "--force"])
  end

  defp mix(args) do
    {program, args} =
      case :os.type() do
        {:win32, _} -> {"cmd", ["/c", "mix" | args]}
        _unix -> {"mix", args}
      end

    System.cmd(program, args, into: IO.stream(), stderr_to_stdout: true)
  end

  defp verify do
    Code.prepend_path(Path.join(Mix.Project.build_path(), "lib/cauldron_gpu/ebin"))

    case Setup.card_status() do
      {:ok, device, backends} ->
        Mix.shell().info(
          "The graphics card is ready: #{device} (#{Enum.map_join(backends, ", ", &Atom.to_string/1)}). Games draw on it by default."
        )

      {:error, text} ->
        Mix.shell().error("Games draw in software: #{text}.")
    end
  end
end
