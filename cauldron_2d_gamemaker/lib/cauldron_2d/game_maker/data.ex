defmodule Cauldron2D.GameMaker.Data do
  @moduledoc """
  A GameMaker game's data file read whole: `data.win` on Windows, `game.ios` on macOS
  and iOS, `game.unx` on Linux, `game.droid` on Android. Every platform's file has the
  same layout.

      {:ok, data} = Cauldron2D.GameMaker.Data.read("path/to/data.win")
      data.general.name
      Enum.map(data.rooms, & &1.name)

  Resources are lists in the game's own order, so a resource's index, which the game's
  code and other resources refer to it by, is its place in its list. `textures` are the
  texture pages, still encoded; `Cauldron2D.GameMaker.Pictures` decodes them. `audio`
  holds the stored sounds' bytes, indexed by `Cauldron2D.GameMaker.Sound`'s `audio`.

  `general.runtime` is the GameMaker version that wrote the file
  (`Cauldron2D.GameMaker.Runtime`); the layout each resource is read with follows it.

  `options` is `nil` when the file's options use the older layout
  (`Cauldron2D.GameMaker.Options`).

  A file whose game code is compiled to bytecode keeps that code in its `CODE`,
  `VARI` and `FUNC` chunks; `bytecode?/1` tells such a file from one whose code was
  compiled into the executable. The bytecode itself is not read here.
  """

  alias Cauldron2D.GameMaker.Background
  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Chunks
  alias Cauldron2D.GameMaker.Font
  alias Cauldron2D.GameMaker.General
  alias Cauldron2D.GameMaker.Object
  alias Cauldron2D.GameMaker.Options
  alias Cauldron2D.GameMaker.Path, as: GamePath
  alias Cauldron2D.GameMaker.Region
  alias Cauldron2D.GameMaker.Room
  alias Cauldron2D.GameMaker.Script
  alias Cauldron2D.GameMaker.Sound
  alias Cauldron2D.GameMaker.Sprite
  alias Cauldron2D.GameMaker.Texture

  @named [:sprites, :backgrounds, :objects, :rooms, :sounds, :fonts, :paths, :scripts]

  @enforce_keys [:general, :chunks]
  defstruct [
    :general,
    :options,
    :chunks,
    sprites: [],
    backgrounds: [],
    objects: [],
    rooms: [],
    sounds: [],
    audio: [],
    audio_groups: [],
    fonts: [],
    paths: [],
    scripts: [],
    textures: [],
    names: %{}
  ]

  @type t :: %__MODULE__{
          general: General.t(),
          options: Options.t() | nil,
          chunks: Chunks.t(),
          sprites: [Sprite.t()],
          backgrounds: [Background.t()],
          objects: [Object.t()],
          rooms: [Room.t()],
          sounds: [Sound.t()],
          audio: [binary()],
          audio_groups: [String.t()],
          fonts: [Font.t()],
          paths: [GamePath.t()],
          scripts: [Script.t()],
          textures: [Texture.t()],
          names: %{atom() => %{String.t() => non_neg_integer()}}
        }

  @doc "The data file at `path`."
  @spec read(Path.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    with {:ok, bytes} <- File.read(path), do: parse(bytes)
  end

  @doc "The data file in `bytes`."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_a_data_file | :no_header}
  def parse(bytes) do
    with {:ok, chunks} <- Chunks.index(bytes),
         {:ok, {header, _size}} <- Map.fetch(chunks, "GEN8") |> header() do
      general = General.read(bytes, header, chunks)
      {:ok, resources(bytes, chunks, general)}
    end
  end

  @doc """
  The stored sounds of the audio group file at `path` (`audiogroup1.dat` and on, beside
  the data file), indexed as `Cauldron2D.GameMaker.Sound`'s `audio` for sounds whose
  `group` is that number.
  """
  @spec audio_group(Path.t()) :: {:ok, [binary()]} | {:error, term()}
  def audio_group(path) do
    with {:ok, bytes} <- File.read(path),
         {:ok, chunks} <- Chunks.index(bytes) do
      {:ok, chunk(chunks, "AUDO", [], &Sound.audio(bytes, &1))}
    end
  end

  @doc "Whether the game's code is carried in the data file as bytecode."
  @spec bytecode?(t()) :: boolean()
  def bytecode?(%__MODULE__{chunks: chunks}), do: Chunks.filled?(chunks, "CODE")

  @doc """
  The index of the resource called `name` in `list`, `nil` if there is none; the first
  of that name when several share it. `list` is one of `:sprites`, `:backgrounds`,
  `:objects`, `:rooms`, `:sounds`, `:fonts`, `:paths` and `:scripts`.
  """
  @spec index(t(), atom(), String.t()) :: non_neg_integer() | nil
  def index(%__MODULE__{names: names}, list, name), do: names |> Map.fetch!(list) |> Map.get(name)

  defp header({:ok, found}), do: {:ok, found}
  defp header(:error), do: {:error, :no_header}

  defp resources(bytes, chunks, %General{format: format} = general) do
    regions = chunk(chunks, "TPAG", %{}, &Region.read_all(bytes, &1))
    rooms = list(bytes, chunks, "ROOM")
    instance_size = Room.instance_size(bytes, rooms, default_instance_size(format))

    %__MODULE__{
      general: general,
      chunks: chunks,
      options: chunk(chunks, "OPTN", nil, &options(bytes, &1)),
      textures: textures(bytes, chunks),
      sprites: each(bytes, chunks, "SPRT", &Sprite.read(bytes, &1, regions, general)),
      backgrounds: each(bytes, chunks, "BGND", &Background.read(bytes, &1, regions, general)),
      objects: each(bytes, chunks, "OBJT", &Object.read(bytes, &1, general)),
      rooms: Enum.map(rooms, &Room.read(bytes, &1, general, instance_size)),
      sounds: each(bytes, chunks, "SOND", &Sound.read(bytes, &1, general)),
      audio: chunk(chunks, "AUDO", [], &Sound.audio(bytes, &1)),
      audio_groups: each(bytes, chunks, "AGRP", &Bytes.string_at(bytes, &1)),
      fonts: each(bytes, chunks, "FONT", &Font.read(bytes, &1, regions, general)),
      paths: each(bytes, chunks, "PATH", &GamePath.read(bytes, &1)),
      scripts: each(bytes, chunks, "SCPT", &Script.read(bytes, &1))
    }
    |> named()
  end

  defp named(data), do: %{data | names: Map.new(@named, &{&1, names(Map.fetch!(data, &1))})}

  defp names(resources) do
    resources
    |> Enum.with_index()
    |> Enum.reverse()
    |> Map.new(fn {resource, index} -> {resource.name, index} end)
  end

  defp default_instance_size(:gms1), do: 36
  defp default_instance_size(:gms2), do: 44
  defp default_instance_size(:gms2_3), do: 48

  defp options(bytes, at) do
    case Options.read(bytes, at) do
      {:ok, options} -> options
      {:error, :old_layout} -> nil
    end
  end

  defp textures(bytes, chunks) do
    case Map.fetch(chunks, "TXTR") do
      {:ok, {at, size}} when size > 0 -> Texture.read_all(bytes, at, size)
      _ -> []
    end
  end

  defp chunk(chunks, name, empty, read) do
    case Map.fetch(chunks, name) do
      {:ok, {at, size}} when size > 0 -> read.(at)
      _ -> empty
    end
  end

  defp list(bytes, chunks, name), do: chunk(chunks, name, [], &Bytes.pointers(bytes, &1))

  defp each(bytes, chunks, name, read), do: bytes |> list(chunks, name) |> Enum.map(read)
end
