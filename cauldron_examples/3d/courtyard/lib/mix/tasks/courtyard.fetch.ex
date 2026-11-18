defmodule Mix.Tasks.Courtyard.Fetch do
  @shortdoc "Download the alley and atrium scenes and the character for mix courtyard"

  @moduledoc """
  Downloads the scenes the courtyard switches to, into the cache folder
  `Courtyard.Assets.root/0` names, checking every file.

      mix courtyard.fetch            # all three
      mix courtyard.fetch alley      # Poly Haven's CC0 models, 87 MB
      mix courtyard.fetch atrium     # Intel's Sponza, about 2.1 GB downloaded
      mix courtyard.fetch character  # the VRoid Project's CC0 avatar, 17 MB

  A fetch that stops can be run again and carries on. The atrium keeps its textures at
  2048 and 1024 pixels a side, not the 4K originals.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    scenes =
      case argv do
        [] -> [:alley, :atrium, :character]
        names -> Enum.map(names, &scene/1)
      end

    Enum.each(scenes, fn scene ->
      Mix.shell().info("fetching #{scene} into #{Courtyard.Assets.folder(scene)}")

      case Courtyard.Fetch.run(scene, &report/1) do
        :ok -> Mix.shell().info("\n#{scene} is ready")
        {:error, reason} -> Mix.raise("\n#{scene} could not be fetched: #{inspect(reason)}")
      end
    end)
  end

  defp scene("alley"), do: :alley
  defp scene("atrium"), do: :atrium
  defp scene("character"), do: :character
  defp scene(other), do: Mix.raise("unknown download #{other}: alley, atrium or character")

  defp report({scene, done, total}), do: progress("#{scene}: #{done} of #{total} files")
  defp report({:atrium, :buffer}), do: progress("atrium: geometry (140 MB)")
  defp report({:character, :file}), do: progress("character: AvatarSample_D_Darkness.vrm")

  defp report({:atrium, :textures, done, total}),
    do: progress("atrium: #{done} of #{total} textures")

  defp progress(text), do: IO.write("\r\e[2K" <> text)
end
