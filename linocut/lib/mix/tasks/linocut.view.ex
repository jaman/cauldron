defmodule Mix.Tasks.Linocut.View do
  @shortdoc "Show pictures in this terminal: a script's rasters, a .png or .pic, or a directory of them"

  @moduledoc """
  Draw pictures in this terminal: an Elixir script whose last expression is a
  `FrenchCurve.Raster`, a list of them, or a `Linocut.Strip`; a `.png` or `.pic` file;
  or a directory, every `.png` and `.pic` in it on one sheet in name order.

      mix linocut.view examples/ship.exs
      mix linocut.view priv/art
      mix linocut.view priv/art/ship.png --protocol braille --columns 8

  ## Options

    * `--protocol` — `kitty`, `iterm2`, `sixel` or `braille`. Default: detected
    * `--columns` — rasters per row on the sheet. Default `8`
    * `--scale` — enlarge each raster by a whole factor first. Default `1`
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, [path | _], _} =
      OptionParser.parse(args, strict: [protocol: :string, columns: :integer, scale: :integer])

    Mix.Task.run("app.start")

    path
    |> pictures()
    |> Enum.map(&Linocut.scale(&1, Keyword.get(opts, :scale, 1)))
    |> Linocut.Preview.sheet(columns: Keyword.get(opts, :columns, 8))
    |> Linocut.Preview.to_terminal(protocol_opt(opts))
    |> then(&IO.write([&1, "\n"]))
  end

  defp pictures(path) do
    cond do
      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.sort()
        |> Enum.filter(&(Path.extname(&1) in [".png", ".pic"]))
        |> Enum.map(&load!(Path.join(path, &1)))

      Path.extname(path) in [".png", ".pic"] ->
        [load!(path)]

      true ->
        {result, _binding} = Code.eval_file(path)
        rasters(result)
    end
  end

  defp load!(path) do
    case Linocut.load(path) do
      {:ok, raster} -> raster
      {:error, reason} -> Mix.raise("could not read #{path}: #{inspect(reason)}")
    end
  end

  defp rasters(%FrenchCurve.Raster{} = raster), do: [raster]
  defp rasters(%Linocut.Strip{frames: frames}), do: Tuple.to_list(frames)
  defp rasters(list) when is_list(list), do: list

  defp protocol_opt(opts) do
    case Keyword.get(opts, :protocol) do
      nil -> []
      name -> [protocol: String.to_existing_atom(name)]
    end
  end
end
