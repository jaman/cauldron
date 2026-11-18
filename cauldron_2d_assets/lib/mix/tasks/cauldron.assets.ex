defmodule Mix.Tasks.Cauldron.Assets do
  @shortdoc "Make a game's art from its assets.exs with NxDiffusion Studio"

  @moduledoc """
  Build the art a game's `assets.exs` asks for (`Cauldron2D.Assets.Build`).

      mix cauldron.assets
      mix cauldron.assets --only jar --only squall
      mix cauldron.assets --only 'hero_*'
      mix cauldron.assets --again jar
      mix cauldron.assets --manifest art/assets.exs --out priv/art

  `--again` asks for new candidates for an asset whose spec has not changed. The Studio
  must be running; see `Cauldron2D.Assets.Studio` for where it is looked for.
  """

  use Mix.Task

  alias Cauldron2D.Assets.Build

  @impl Mix.Task
  def run(argv) do
    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [manifest: :string, out: :string, only: :keep, again: :keep]
      )

    Application.ensure_all_started(:req)

    build_opts = [
      out: Keyword.get(opts, :out, "priv/art"),
      only: patterns(opts),
      again: names(opts, :again) || []
    ]

    case Build.run(Keyword.get(opts, :manifest, "assets.exs"), build_opts) do
      {:ok, _lock} -> :ok
      {:error, reason} -> Mix.raise("cauldron.assets stopped: #{inspect(reason)}")
    end
  end

  defp patterns(opts) do
    case Keyword.get_values(opts, :only) do
      [] -> nil
      names -> Enum.map(names, &if(String.contains?(&1, "*"), do: &1, else: String.to_atom(&1)))
    end
  end

  defp names(opts, key) do
    case Keyword.get_values(opts, key) do
      [] -> nil
      names -> Enum.map(names, &String.to_atom/1)
    end
  end
end
