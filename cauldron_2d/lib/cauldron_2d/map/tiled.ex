defmodule Cauldron2D.Map.Tiled do
  @moduledoc """
  Levels made in [Tiled](https://www.mapeditor.org): `.tmj` (JSON) and `.tmx` (XML)
  orthogonal maps, finite or infinite, read into plain data a game builds its world from.

      {:ok, level} = Cauldron2D.Map.Tiled.read("priv/maps/forest.tmj")
      ground = Cauldron2D.Map.Tiled.layer(level, "ground").tiles
      spawns = Cauldron2D.Map.Tiled.objects(level, "spawns")

  A level is `%{width, height, tile_width, tile_height, properties, tilesets, layers}`,
  sizes in tiles and pixels as Tiled gives them. Each layer is one of:

    * `%{kind: :tiles, name, visible?, properties, tiles, flips}` — `tiles` maps
      `{x, y}` to the tile's global id (`0` cells are left out); `flips` maps the cells
      drawn flipped to a list of `:horizontal`, `:vertical` and `:diagonal`
    * `%{kind: :objects, name, visible?, properties, objects}` — each object `%{id, name,
      type, x, y, width, height, properties}` with its place and size in tiles (pixels
      over the tile size), and `gid` for a tile object
    * `%{kind: :image, name, visible?, properties, image}`

  Layers inside groups are listed in order with their group's name before theirs,
  `"group/layer"`. Properties are maps from name to value, typed as Tiled types them.
  Tile data may be a list, CSV, or base64, uncompressed or compressed with zlib or gzip;
  zstd is not read. A tileset is `%{first_gid, name, columns, count, image}`; an external
  tileset (`source`) is named by its file.
  """

  import Bitwise

  alias Cauldron2D.Map.Tiled.Xml

  @flipped_h 0x80000000
  @flipped_v 0x40000000
  @flipped_d 0x20000000
  @gid_bits 0x0FFFFFFF

  @type level :: map()

  @doc "The level in the file at `path`, `.tmx` read as XML and anything else as JSON."
  @spec read(Path.t()) :: {:ok, level()} | {:error, term()}
  def read(path) do
    with {:ok, text} <- File.read(path) do
      if Path.extname(path) == ".tmx", do: parse(text, :tmx), else: parse(text, :tmj)
    end
  end

  @doc "The level in `text`, a `.tmj` (`:tmj`) or `.tmx` (`:tmx`) file's contents."
  @spec parse(binary(), :tmj | :tmx) :: {:ok, level()} | {:error, term()}
  def parse(text, :tmx), do: with({:ok, raw} <- Xml.decode(text), do: level(raw))

  def parse(text, :tmj) do
    case JSON.decode(text) do
      {:ok, raw} -> level(raw)
      {:error, reason} -> {:error, {:tmj, reason}}
    end
  end

  @doc "The layer named `name`, or `nil`."
  @spec layer(level(), String.t()) :: map() | nil
  def layer(level, name), do: Enum.find(level.layers, &(&1.name == name))

  @doc "The objects of the object layer named `name`; `[]` when there is none."
  @spec objects(level(), String.t()) :: [map()]
  def objects(level, name) do
    case layer(level, name) do
      %{kind: :objects, objects: objects} -> objects
      _other -> []
    end
  end

  defp level(raw) do
    {tile_width, tile_height} = {raw["tilewidth"], raw["tileheight"]}

    {:ok,
     %{
       width: raw["width"],
       height: raw["height"],
       tile_width: tile_width,
       tile_height: tile_height,
       properties: properties(raw["properties"]),
       tilesets: Enum.map(raw["tilesets"] || [], &tileset/1),
       layers: layers(raw["layers"] || [], "", {tile_width, tile_height})
     }}
  rescue
    error -> {:error, {:tiled, Exception.message(error)}}
  end

  defp tileset(raw),
    do: %{
      first_gid: raw["firstgid"],
      name: raw["name"] || raw["source"],
      columns: raw["columns"],
      count: raw["tilecount"],
      image: raw["image"]
    }

  defp layers(raws, prefix, tile) do
    Enum.flat_map(raws, fn
      %{"type" => "group"} = group ->
        layers(group["layers"] || [], prefix <> group["name"] <> "/", tile)

      raw ->
        [layer(raw, prefix <> (raw["name"] || ""), tile)]
    end)
  end

  defp layer(%{"type" => "tilelayer"} = raw, name, _tile) do
    {tiles, flips} = cells(raw)
    Map.merge(common(raw, name), %{kind: :tiles, tiles: tiles, flips: flips})
  end

  defp layer(%{"type" => "objectgroup"} = raw, name, tile),
    do:
      Map.merge(common(raw, name), %{
        kind: :objects,
        objects: Enum.map(raw["objects"] || [], &object(&1, tile))
      })

  defp layer(%{"type" => "imagelayer"} = raw, name, _tile),
    do: Map.merge(common(raw, name), %{kind: :image, image: raw["image"]})

  defp common(raw, name),
    do: %{
      name: name,
      visible?: raw["visible"] not in [false, 0, "0"],
      properties: properties(raw["properties"])
    }

  defp object(raw, {tile_width, tile_height}) do
    base = %{
      id: raw["id"],
      name: raw["name"] || "",
      type: raw["type"] || raw["class"] || "",
      x: (raw["x"] || 0) / tile_width,
      y: (raw["y"] || 0) / tile_height,
      width: (raw["width"] || 0) / tile_width,
      height: (raw["height"] || 0) / tile_height,
      properties: properties(raw["properties"])
    }

    if raw["gid"], do: Map.put(base, :gid, band(raw["gid"], @gid_bits)), else: base
  end

  defp cells(%{"chunks" => chunks} = raw) when is_list(chunks) do
    Enum.reduce(chunks, {%{}, %{}}, fn chunk, {tiles, flips} ->
      encoded =
        Map.merge(
          Map.take(raw, ["encoding", "compression"]),
          Map.take(chunk, ["data", "compression"])
        )

      {more_tiles, more_flips} = place(numbers(encoded), chunk["width"], {chunk["x"], chunk["y"]})
      {Map.merge(tiles, more_tiles), Map.merge(flips, more_flips)}
    end)
  end

  defp cells(raw), do: place(numbers(raw), raw["width"], {0, 0})

  defp place(numbers, width, {ox, oy}) do
    numbers
    |> Enum.with_index()
    |> Enum.reduce({%{}, %{}}, fn
      {0, _index}, acc ->
        acc

      {raw, index}, {tiles, flips} ->
        at = {ox + rem(index, width), oy + div(index, width)}
        tiles = Map.put(tiles, at, band(raw, @gid_bits))

        case flip(raw) do
          [] -> {tiles, flips}
          flip -> {tiles, Map.put(flips, at, flip)}
        end
    end)
  end

  defp flip(raw) do
    for {bit, name} <- [
          {@flipped_h, :horizontal},
          {@flipped_v, :vertical},
          {@flipped_d, :diagonal}
        ],
        band(raw, bit) != 0,
        do: name
  end

  defp numbers(%{"encoding" => "base64", "data" => data} = raw) do
    bytes = data |> String.trim() |> Base.decode64!() |> inflate(raw["compression"])
    for <<gid::little-unsigned-32 <- bytes>>, do: gid
  end

  defp numbers(%{"data" => data}) when is_list(data), do: data

  defp inflate(bytes, compression) when compression in [nil, ""], do: bytes
  defp inflate(bytes, "zlib"), do: :zlib.uncompress(bytes)
  defp inflate(bytes, "gzip"), do: :zlib.gunzip(bytes)

  defp inflate(_bytes, other),
    do: raise(ArgumentError, "tile data compressed with #{other} is not read")

  defp properties(nil), do: %{}

  defp properties(list) when is_list(list),
    do: Map.new(list, &{&1["name"], value(&1["type"], &1["value"])})

  defp value("int", value) when is_binary(value), do: String.to_integer(value)
  defp value("float", value) when is_binary(value), do: String.to_float(normal_float(value))
  defp value("bool", value) when is_binary(value), do: value == "true"
  defp value(_type, value), do: value

  defp normal_float(value), do: if(String.contains?(value, "."), do: value, else: value <> ".0")
end
