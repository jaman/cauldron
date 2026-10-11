defmodule Mix.Tasks.Gamemaker.Info do
  @shortdoc "Lists what a GameMaker data file holds"

  @moduledoc """
  Prints what a GameMaker data file holds: the game, the GameMaker generation that
  built it, whether its code is bytecode or compiled into the executable, and its
  resources.

      mix gamemaker.info path/to/data.win
      mix gamemaker.info path/to/game.ios --list rooms
      mix gamemaker.info path/to/data.win --list objects

  `--list` prints one line per resource of a kind: `rooms`, `sprites`, `backgrounds`,
  `objects`, `sounds`, `fonts`, `paths` or `scripts`.
  """

  use Mix.Task

  alias Cauldron2D.GameMaker.Data
  alias Cauldron2D.GameMaker.Room

  @kinds ~w(rooms sprites backgrounds objects sounds fonts paths scripts)

  @impl Mix.Task
  def run(args) do
    {opts, paths} = OptionParser.parse!(args, strict: [list: :string])

    with [path] <- paths,
         {:ok, data} <- Data.read(path) do
      print(data, opts[:list])
    else
      [] -> Mix.raise("Usage: mix gamemaker.info PATH [--list KIND]")
      {:error, reason} -> Mix.raise("Could not read #{hd(paths)}: #{inspect(reason)}")
    end
  end

  defp print(data, nil) do
    general = data.general
    {major, minor, release, build} = general.version

    Mix.shell().info("""
    #{general.display_name} (#{general.name}), version #{major}.#{minor}.#{release}.#{build}
    #{format(general.format)}, bytecode version #{general.bytecode}
    code: #{if Data.bytecode?(data), do: "bytecode in the data file", else: "compiled into the executable"}
    window #{elem(general.window, 0)}x#{elem(general.window, 1)}#{fps(general.fps)}
    #{Enum.map_join(@kinds, "\n", &"#{&1}: #{length(Map.fetch!(data, String.to_existing_atom(&1)))}")}
    texture pages: #{length(data.textures)} (#{data.textures |> Enum.map(& &1.encoding) |> Enum.uniq() |> Enum.join(", ")})
    stored sounds: #{length(data.audio)}
    """)
  end

  defp print(data, kind) when kind in @kinds do
    data
    |> Map.fetch!(String.to_existing_atom(kind))
    |> Enum.with_index()
    |> Enum.each(fn {resource, index} ->
      Mix.shell().info("#{index}\t#{line(resource, data)}")
    end)
  end

  defp print(_data, kind),
    do: Mix.raise("Unknown kind #{kind}; one of #{Enum.join(@kinds, ", ")}")

  defp line(%Room{} = room, _data) do
    {width, height} = room.size

    "#{room.name}\t#{width}x#{height}\t#{length(room.instances)} instances\t#{length(room.layers)} layers\t#{length(room.tiles)} tiles"
  end

  defp line(%Cauldron2D.GameMaker.Sprite{} = sprite, _data) do
    {width, height} = sprite.size

    "#{sprite.name}\t#{width}x#{height}\t#{length(sprite.frames)} frames\torigin #{inspect(sprite.origin)}"
  end

  defp line(%Cauldron2D.GameMaker.Object{} = object, data) do
    sprite = if object.sprite >= 0, do: Enum.at(data.sprites, object.sprite).name, else: "-"
    parent = if object.parent, do: Enum.at(data.objects, object.parent).name, else: "-"

    events =
      Enum.map_join(object.events, " ", fn {type, subtype, _code} -> "#{type}:#{subtype}" end)

    "#{object.name}\tsprite #{sprite}\tparent #{parent}\tdepth #{object.depth}\t#{events}"
  end

  defp line(%Cauldron2D.GameMaker.Sound{} = sound, _data),
    do:
      "#{sound.name}\t#{sound.file}\t#{if sound.audio, do: "stored #{sound.audio}", else: "file beside the game"}\tgroup #{sound.group}"

  defp line(%{name: name}, _data), do: name

  defp format(:gms1), do: "GameMaker: Studio 1"
  defp format(:gms2), do: "GameMaker Studio 2"
  defp format(:gms2_3), do: "GameMaker Studio 2.3 or later"

  defp fps(nil), do: ""
  defp fps(fps), do: ", #{fps} steps a second"
end
