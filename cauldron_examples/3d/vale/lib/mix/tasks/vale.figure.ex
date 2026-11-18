defmodule Mix.Tasks.Vale.Figure do
  @shortdoc "Copy the walker's figure and clips out of the imachine library"

  @moduledoc """
  Copies the walker's files from an imachine library into `Vale.Figure.folder/0`.

      mix vale.figure
      mix vale.figure --library /path/to/renders

  `priv/figure.json` names the library folder, the library item the figure is taken
  from and the item of each clip; every item's `motion.glb` is copied. `--library`
  names another folder.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [library: :string])
    manifest = :vale |> :code.priv_dir() |> Path.join("figure.json") |> File.read!() |> JSON.decode!()
    library = Path.expand(Keyword.get(opts, :library, manifest["library"]))
    File.mkdir_p!(Vale.Figure.folder())

    [{"figure", manifest["figure"]} | Map.to_list(manifest["clips"])]
    |> Enum.each(fn {name, item} -> copy(library, item, name) end)
  end

  defp copy(library, item, name) do
    source = Path.join([library, item, "motion.glb"])
    target = Vale.Figure.file(name)

    case File.cp(source, target) do
      :ok -> Mix.shell().info("#{name}: #{target}")
      {:error, reason} -> Mix.raise("cannot copy #{source}: #{:file.format_error(reason)}")
    end
  end
end
