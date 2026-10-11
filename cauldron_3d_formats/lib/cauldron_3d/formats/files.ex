defmodule Cauldron3D.Formats.Files do
  @moduledoc """
  A game's files, gathered from one or more directories: the files loose in each, those in
  its numbered `pak0.pak`, `pak1.pak`, … archives, and those in its `.pk3` zip archives,
  including `.pk3` archives held inside them. Names are matched without regard to case.

      {:ok, files} = Cauldron3D.Formats.Files.open("/games/quake", within: "id1")
      Cauldron3D.Formats.Files.read(files, "maps/e1m1.bsp")

      {:ok, files} = Cauldron3D.Formats.Files.open(["/games/half-life/valve", "/mods/freehl"])

  Within a directory, `.pak` archives come first in number order, then `.pk3` archives in
  name order, then loose files; a later source overrides an earlier one, and a later
  directory overrides an earlier directory.

  ## Options

    * `:within` — a subdirectory to use instead of a given directory that holds no
      archives, as a game's data directory beneath its install (`"id1"`, say)
  """

  @enforce_keys [:dirs, :entries]
  defstruct [:dirs, :entries]

  @type source :: Path.t() | {:inner, binary()}
  @type entry ::
          {:pak, Path.t(), non_neg_integer(), non_neg_integer()}
          | {:zip, source(), charlist()}
          | {:loose, Path.t()}
  @type t :: %__MODULE__{dirs: [Path.t()], entries: %{String.t() => entry()}}

  @doc "The files of the directory or directories `paths`."
  @spec open(Path.t() | [Path.t()], keyword()) ::
          {:ok, t()} | {:error, :no_game_directory | :not_a_pak}
  def open(paths, opts \\ [])

  def open(path, opts) when is_binary(path), do: open([path], opts)

  def open(paths, opts) when is_list(paths) do
    Enum.reduce_while(paths, {:ok, %__MODULE__{dirs: [], entries: %{}}}, fn path, {:ok, acc} ->
      with {:ok, dir} <- game_dir(Path.expand(path), Keyword.get(opts, :within)),
           {:ok, entries} <- entries(dir) do
        {:cont, {:ok, %{acc | dirs: acc.dirs ++ [dir], entries: Map.merge(acc.entries, entries)}}}
      else
        error -> {:halt, error}
      end
    end)
  end

  @doc "As `open/2`, raising `ArgumentError` on failure."
  @spec open!(Path.t() | [Path.t()], keyword()) :: t()
  def open!(paths, opts \\ []) do
    case open(paths, opts) do
      {:ok, files} ->
        files

      {:error, reason} ->
        raise ArgumentError, "cannot open game files at #{inspect(paths)}: #{reason}"
    end
  end

  @doc "The file `name`'s bytes, or `nil` when there is none."
  @spec read(t(), String.t()) :: binary() | nil
  def read(%__MODULE__{entries: entries}, name) do
    case Map.get(entries, String.downcase(name)) do
      nil -> nil
      entry -> read_entry(entry)
    end
  end

  @doc "As `read/2`, raising `KeyError` when the file is missing."
  @spec read!(t(), String.t()) :: binary()
  def read!(files, name), do: read(files, name) || raise(KeyError, key: name, term: :game_files)

  @doc """
  The package file `name` comes from: the archive's file name for a file in a `.pak` or
  `.pk3` (the outer archive for one inside another), or the directory's own name for a
  loose file; `nil` when there is no such file.
  """
  @spec package(t(), String.t()) :: String.t() | nil
  def package(%__MODULE__{entries: entries}, name) do
    case Map.get(entries, String.downcase(name)) do
      nil -> nil
      {:pak, path, _, _} -> Path.basename(path)
      {:zip, {:inner, _}, _} -> "inner.pk3"
      {:zip, path, _} -> Path.basename(path)
      {:loose, path} -> loose_dir(path, name)
    end
  end

  defp loose_dir(path, name) do
    depth = name |> Path.split() |> length()
    path |> Path.split() |> Enum.drop(-depth) |> List.last()
  end

  @doc "Whether file `name` is there."
  @spec exists?(t(), String.t()) :: boolean()
  def exists?(%__MODULE__{entries: entries}, name),
    do: Map.has_key?(entries, String.downcase(name))

  @doc "The names of the files, lower case, that begin with `prefix`, sorted."
  @spec list(t(), String.t()) :: [String.t()]
  def list(%__MODULE__{entries: entries}, prefix \\ "") do
    prefix = String.downcase(prefix)
    entries |> Map.keys() |> Enum.filter(&String.starts_with?(&1, prefix)) |> Enum.sort()
  end

  defp game_dir(path, within) do
    sub = within && child(path, within)

    cond do
      File.dir?(path) and archives?(path) -> {:ok, path}
      sub && File.dir?(sub) -> {:ok, sub}
      File.dir?(path) -> {:ok, path}
      true -> {:error, :no_game_directory}
    end
  end

  defp archives?(dir), do: paks(dir) != [] or pk3s(dir) != []

  defp child(path, name) do
    with {:ok, names} <- File.ls(path),
         found when found != nil <-
           Enum.find(names, &(String.downcase(&1) == String.downcase(name))) do
      Path.join(path, found)
    else
      _ -> nil
    end
  end

  defp entries(dir) do
    with {:ok, packed} <- packed(dir) do
      zipped = dir |> pk3s() |> Enum.map(&zip_entries(&1)) |> Enum.reduce(%{}, &Map.merge(&2, &1))
      {:ok, packed |> Map.merge(zipped) |> Map.merge(loose(dir))}
    end
  end

  defp paks(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names |> Enum.flat_map(&numbered(dir, &1)) |> Enum.sort() |> Enum.map(&elem(&1, 1))

      {:error, _} ->
        []
    end
  end

  defp pk3s(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(String.downcase(&1), ".pk3"))
        |> Enum.sort_by(&String.downcase/1)
        |> Enum.map(&Path.join(dir, &1))

      {:error, _} ->
        []
    end
  end

  defp numbered(dir, name) do
    case Regex.run(~r/^pak(\d+)\.pak$/, String.downcase(name)) do
      [_, number] -> [{String.to_integer(number), Path.join(dir, name)}]
      nil -> []
    end
  end

  defp packed(dir) do
    Enum.reduce_while(paks(dir), {:ok, %{}}, fn path, {:ok, acc} ->
      case directory(path) do
        {:ok, entries} -> {:cont, {:ok, Map.merge(acc, entries)}}
        error -> {:halt, error}
      end
    end)
  end

  defp directory(path) do
    case pread(path, 0, 12) do
      <<"PACK", offset::little-32, size::little-32>> ->
        entries =
          for <<name::binary-56, at::little-32, length::little-32 <- pread(path, offset, size)>>,
            into: %{},
            do:
              {name |> :binary.split(<<0>>) |> hd() |> String.downcase(),
               {:pak, path, at, length}}

        {:ok, entries}

      _ ->
        {:error, :not_a_pak}
    end
  end

  defp zip_entries(source) do
    case :zip.list_dir(zip_handle(source)) do
      {:ok, [_comment | files]} ->
        names = for {:zip_file, name, info, _, _, _} <- files, elem(info, 2) == :regular, do: name

        Enum.reduce(names, %{}, &zip_entry(source, &1, &2))

      _ ->
        %{}
    end
  end

  defp zip_entry(source, name, acc) do
    lower = name |> List.to_string() |> String.downcase()

    if String.ends_with?(lower, ".pk3"),
      do: Map.merge(acc, zip_entries({:inner, read_entry({:zip, source, name})})),
      else: Map.put(acc, lower, {:zip, source, name})
  end

  defp zip_handle({:inner, bytes}), do: bytes
  defp zip_handle(path), do: String.to_charlist(path)

  defp loose(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.reject(&(File.dir?(&1) or archive?(&1)))
    |> Map.new(&{&1 |> Path.relative_to(dir) |> String.downcase(), {:loose, &1}})
  end

  defp archive?(path) do
    lower = String.downcase(path)
    String.ends_with?(lower, ".pak") or String.ends_with?(lower, ".pk3")
  end

  defp read_entry({:loose, path}), do: File.read!(path)
  defp read_entry({:pak, path, offset, length}), do: pread(path, offset, length)

  defp read_entry({:zip, source, name}) do
    case :zip.extract(zip_handle(source), [{:file_list, [name]}, :memory]) do
      {:ok, [{_name, bytes}]} -> bytes
      _ -> nil
    end
  end

  defp pread(path, offset, length) do
    {:ok, file} = :file.open(path, [:read, :binary, :raw])

    try do
      case :file.pread(file, offset, length) do
        {:ok, data} -> data
        _ -> <<>>
      end
    after
      :file.close(file)
    end
  end
end
