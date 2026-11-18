defmodule Mix.Tasks.Cauldron.Assets.Pick do
  @shortdoc "Choose one of an asset's candidates"

  @moduledoc """
  Choose candidate `INDEX` (from `0`, as the sheet in `priv/art/.candidates` numbers
  them) for asset `NAME`, record it in `assets.lock.exs`, and write it into the art
  directory.

      mix cauldron.assets.pick jar 2
      mix cauldron.assets.pick jar 2 --manifest art/assets.exs --out priv/art
  """

  use Mix.Task

  alias Cauldron2D.Assets.{Build, Lock}

  @impl Mix.Task
  def run(argv) do
    {opts, args, _invalid} = OptionParser.parse(argv, strict: [manifest: :string, out: :string])
    manifest = Keyword.get(opts, :manifest, "assets.exs")

    with [name, index] <- args,
         {index, ""} <- Integer.parse(index),
         name = String.to_atom(name),
         lock_path = Build.lock_path(manifest),
         {:ok, lock} <- Lock.pick(Lock.read(lock_path), name, index),
         :ok <- Lock.write(lock_path, lock),
         :ok <- Build.write_pick(manifest, name, out: Keyword.get(opts, :out, "priv/art")) do
      Mix.shell().info("#{name}: candidate #{index} written")
    else
      {:error, reason} -> Mix.raise("cauldron.assets.pick: #{inspect(reason)}")
      _usage -> Mix.raise("usage: mix cauldron.assets.pick NAME INDEX")
    end
  end
end
