defmodule Courtyard.Fetch do
  @moduledoc """
  Downloads the scenes `Courtyard.Assets` keeps, as `priv/assets.json` pins them.

    * `:alley` — every Poly Haven file, checked against its MD5; a file already present
      with the right MD5 is not fetched again
    * `:atrium` — `Courtyard.Fetch.Atrium`
    * `:character` — the avatar's zip, checked against its SHA-256, and the VRM file out of
      it, checked against its own

  `report` is called with each step: `{:alley, done, total}`,
  `{:atrium, :buffer}`, `{:atrium, :textures, done, total}`, `{:character, :file}`.

      Courtyard.Fetch.run(:alley, &IO.inspect/1)
  """

  alias Courtyard.Assets
  alias Courtyard.Fetch.{Atrium, Http}

  @workers 6

  @doc "Fetches `scene`; `:ok` once it is complete and checked."
  @spec run(Assets.scene(), (term() -> term())) :: :ok | {:error, term()}
  def run(:atrium, report), do: Atrium.run(report)

  def run(:character, report) do
    pinned = Assets.manifest()["character"]
    path = Assets.character()

    with {:ok, zip} <- Http.get(pinned["url"]),
         :ok <- sha256_checked(zip, pinned["sha256"], pinned["url"]),
         {:ok, file} <- unzipped(zip, pinned["file"]),
         :ok <- sha256_checked(file, pinned["file_sha256"], pinned["file"]) do
      report.({:character, :file})
      File.mkdir_p!(Path.dirname(path))
      File.write!(path <> ".part", file)
      File.rename!(path <> ".part", path)
      File.write!(Assets.complete_marker(:character), "")
    end
  end

  def run(:alley, report) do
    pinned = Assets.manifest()["alley"]
    folder = Assets.folder(:alley)

    files =
      Enum.flat_map(pinned["models"], fn model ->
        Enum.map(model["files"], &{Path.join(model["id"], &1["path"]), &1})
      end) ++
        Enum.map(pinned["ground"]["files"], &{Path.join("ground", &1["path"]), &1})

    total = length(files)

    files
    |> Task.async_stream(fn {path, file} -> fetched(Path.join(folder, path), file) end,
      max_concurrency: @workers,
      timeout: :infinity
    )
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn
      {{:ok, :ok}, done}, :ok ->
        report.({:alley, done, total})
        {:cont, :ok}

      {{:ok, {:error, reason}}, _done}, :ok ->
        {:halt, {:error, reason}}
    end)
    |> then(fn
      :ok -> File.write!(Assets.complete_marker(:alley), "")
      error -> error
    end)
  end

  defp fetched(path, file) do
    if File.exists?(path) and md5(File.read!(path)) == file["md5"] do
      :ok
    else
      with {:ok, bytes} <- Http.get(file["url"]),
           :ok <- checked(bytes, file) do
        File.mkdir_p!(Path.dirname(path))
        File.write!(path <> ".part", bytes)
        File.rename!(path <> ".part", path)
      end
    end
  end

  defp checked(bytes, file) do
    if md5(bytes) == file["md5"], do: :ok, else: {:error, {:md5, file["url"]}}
  end

  defp md5(bytes), do: :crypto.hash(:md5, bytes) |> Base.encode16(case: :lower)

  defp sha256_checked(bytes, expected, name) do
    if :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) == expected,
      do: :ok,
      else: {:error, {:sha256, name}}
  end

  defp unzipped(zip, name) do
    case :zip.unzip(zip, [:memory, file_list: [String.to_charlist(name)]]) do
      {:ok, [{_name, file}]} -> {:ok, file}
      {:ok, []} -> {:error, {:not_in_zip, name}}
      {:error, reason} -> {:error, {:zip, reason}}
    end
  end
end
