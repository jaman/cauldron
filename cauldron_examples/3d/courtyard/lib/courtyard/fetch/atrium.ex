defmodule Courtyard.Fetch.Atrium do
  @moduledoc """
  Fetches Intel's Sponza for the atrium: the glTF, its buffer and the textures it names,
  read out of Intel's archive over byte ranges, so the archive's other formats are never
  downloaded. The archive's size and the SHA-256 of its central directory must match the
  manifest, and every file its recorded CRC-32. Each texture is written again at each of
  the manifest's sizes (`CauldronGPU.reduce_image/2`) — colour pictures resized in
  linear light, normals and roughness as data — with a glTF for each size naming those
  copies; the full-size originals are not kept. A texture already reduced is skipped, so
  a fetch that stopped carries on where it was.

      Courtyard.Fetch.Atrium.run(&IO.inspect/1)
  """

  alias Courtyard.Assets
  alias Courtyard.Fetch.{Http, Zip}

  @texture_workers 4

  @doc "Fetches the atrium, telling `report` of each step; `:ok` once it is complete."
  @spec run((term() -> term())) :: :ok | {:error, term()}
  def run(report) do
    pinned = Assets.manifest()["atrium"]
    folder = Assets.folder(:atrium)
    File.mkdir_p!(folder)

    with {:ok, location, size} <- Http.located(pinned["url"]),
         :ok <- same(size, pinned["zip_size"], :archive_size),
         {:ok, directory} <- directory(location, pinned),
         {:ok, entries} <- Zip.entries(directory),
         {:ok, gltf} <- Zip.extract(location, Map.fetch!(entries, pinned["gltf"])),
         json = JSON.decode!(gltf),
         base = Path.dirname(pinned["gltf"]),
         :ok <- buffer(location, entries, base, json, folder, report),
         :ok <- textures(location, entries, base, json, folder, pinned["sizes"], report) do
      Enum.each(pinned["sizes"], &write_gltf(json, folder, &1))
      File.write!(Assets.complete_marker(:atrium), "")
      :ok
    end
  end

  defp directory(location, pinned) do
    offset = pinned["directory_offset"]

    with {:ok, bytes} <- Http.range(location, offset, offset + pinned["directory_size"] - 1),
         :ok <-
           same(
             :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower),
             pinned["directory_sha256"],
             :directory
           ) do
      {:ok, bytes}
    end
  end

  defp same(value, value, _what), do: :ok
  defp same(value, pinned, what), do: {:error, {what, :changed, value, pinned}}

  defp buffer(location, entries, base, json, folder, report) do
    target = Path.join(folder, "sponza.bin")

    if File.exists?(target) do
      :ok
    else
      [%{"uri" => uri}] = json["buffers"]
      report.({:atrium, :buffer})

      with {:ok, bytes} <-
             Zip.extract(location, Map.fetch!(entries, Path.join(base, URI.decode(uri)))) do
        File.write!(target <> ".part", bytes)
        File.rename!(target <> ".part", target)
      end
    end
  end

  defp textures(location, entries, base, json, folder, sizes, report) do
    colours = colours(json)
    images = Enum.with_index(json["images"])
    total = length(images)

    images
    |> Task.async_stream(
      fn {image, index} ->
        texture(location, entries, base, image, Map.get(colours, index, :linear), folder, sizes)
      end,
      max_concurrency: @texture_workers,
      timeout: :infinity
    )
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn
      {{:ok, :ok}, done}, :ok ->
        report.({:atrium, :textures, done, total})
        {:cont, :ok}

      {{:ok, {:error, reason}}, _done}, :ok ->
        {:halt, {:error, reason}}
    end)
  end

  defp colours(json) do
    for material <- json["materials"],
        {key, colour} <- [{"baseColorTexture", :srgb}, {"emissiveTexture", :srgb}],
        info = get_in(material, ["pbrMetallicRoughness", key]) || material[key],
        info != nil,
        into: %{},
        do: {Enum.at(json["textures"], info["index"])["source"], colour}
  end

  defp texture(location, entries, base, image, colour, folder, sizes) do
    name = image["uri"] |> URI.decode() |> Path.basename() |> Path.rootname()

    entry = Map.fetch!(entries, Path.join(base, URI.decode(image["uri"])))

    if Enum.all?(sizes, &reduced(folder, &1, name)) do
      :ok
    else
      with {:ok, bytes} <- Zip.extract(location, entry) do
        Enum.reduce_while(sizes, :ok, &reduce_to(&1, &2, bytes, colour, folder, name))
      end
    end
  end

  defp reduce_to(side, :ok, bytes, colour, folder, name) do
    case CauldronGPU.reduce_image(bytes, max_side: side, colour: colour) do
      {:ok, reduced} ->
        write_texture(folder, side, name, reduced)
        {:cont, :ok}

      {:error, reason} ->
        {:halt, {:error, {:reduce, name, reason}}}
    end
  end

  defp reduced(folder, side, name),
    do:
      Enum.any?(
        [".jpg", ".png"],
        &File.exists?(Path.join([folder, "textures_#{side}", name <> &1]))
      )

  defp write_texture(folder, side, name, reduced) do
    dir = Path.join(folder, "textures_#{side}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name <> if(reduced.kind == :png, do: ".png", else: ".jpg"))
    File.write!(path <> ".part", reduced.bytes)
    File.rename!(path <> ".part", path)
  end

  defp write_gltf(json, folder, side) do
    images =
      Enum.map(json["images"], fn image ->
        name = image["uri"] |> URI.decode() |> Path.basename() |> Path.rootname()

        file =
          Enum.find(
            [".jpg", ".png"],
            &File.exists?(Path.join([folder, "textures_#{side}", name <> &1]))
          )

        image
        |> Map.put("uri", "textures_#{side}/" <> URI.encode(name <> file))
        |> Map.delete("mimeType")
      end)

    buffers = Enum.map(json["buffers"], &Map.put(&1, "uri", "sponza.bin"))
    gltf = json |> Map.put("images", images) |> Map.put("buffers", buffers)
    File.write!(Path.join(folder, "sponza_#{side}.gltf"), JSON.encode!(gltf))
  end
end
