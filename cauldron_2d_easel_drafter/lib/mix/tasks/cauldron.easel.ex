defmodule Mix.Tasks.Cauldron.Easel do
  @shortdoc "Edit an art directory in the terminal"

  @moduledoc """
  Open `Cauldron2D.Easel.Drafter` on an art directory.

      mix cauldron.easel priv/art --tile 16
      mix cauldron.easel priv/art --tile 16 --art ship --atlas my_game

  ## Options

    * `--tile` — the tile size in pixels. Required
    * `--art` — an art to open at once
    * `--atlas` — the atlas name saves install into
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, [dir | _], _} =
      OptionParser.parse(args, strict: [tile: :integer, art: :string, atlas: :string])

    Mix.Task.run("app.start")

    props =
      %{dir: dir, tile: Keyword.fetch!(opts, :tile)}
      |> put_if(:art, opts[:art] && String.to_atom(opts[:art]))
      |> put_if(:atlas, opts[:atlas] && String.to_atom(opts[:atlas]))

    Drafter.run(Cauldron2D.Easel.Drafter, props: props)
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
