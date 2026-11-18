defmodule Cauldron2D.Map.Ldtk do
  @moduledoc """
  Levels made in [LDtk](https://ldtk.io): an `.ldtk` project read into plain data a game
  builds its world from, levels kept in separate files (`.ldtkl`) included.

      {:ok, project} = Cauldron2D.Map.Ldtk.read("priv/maps/world.ldtk")
      level = Cauldron2D.Map.Ldtk.level(project, "Level_0")
      walls = Cauldron2D.Map.Ldtk.layer(level, "Collisions").values
      spawns = Cauldron2D.Map.Ldtk.layer(level, "Entities").entities

  A project is `%{grid_size, levels}`. A level is `%{name, x, y, width, height, fields,
  layers}`: its place in the world and its size in pixels, its custom fields, and its
  layers from the top down. Each layer has a `name`, `columns`, `rows` and `grid_size`,
  and by its kind:

    * `%{kind: :int_grid, values}` — `{x, y}` to the cell's value (`0` cells left out)
    * `%{kind: :tiles, tiles}` — for a Tiles or an AutoLayer layer, each tile
      `%{at: {x, y}, tile: id, flips: [...]}`, `at` in cells and `flips` of
      `:horizontal` and `:vertical`; a cell may hold several, drawn in order
    * `%{kind: :entities, entities}` — each `%{id, name, x, y, width, height, fields}`,
      place and size in cells

  Fields are maps from a field's name to its value.
  """

  @type project :: map()

  @doc "The project in the file at `path`, with levels kept in their own files read from beside it."
  @spec read(Path.t()) :: {:ok, project()} | {:error, term()}
  def read(path) do
    with {:ok, text} <- File.read(path),
         {:ok, raw} <- decode(text) do
      project(raw, &read_level(Path.join(Path.dirname(path), &1)))
    end
  end

  @doc "The project in `text`, an `.ldtk` file's contents; its levels must be inside it."
  @spec parse(binary()) :: {:ok, project()} | {:error, term()}
  def parse(text) do
    with {:ok, raw} <- decode(text),
         do:
           project(raw, fn file ->
             raise ArgumentError, "level file #{file} is outside the text"
           end)
  end

  @doc "The level named `name`, or `nil`."
  @spec level(project(), String.t()) :: map() | nil
  def level(project, name), do: Enum.find(project.levels, &(&1.name == name))

  @doc "The layer of `level` named `name`, or `nil`."
  @spec layer(map(), String.t()) :: map() | nil
  def layer(level, name), do: Enum.find(level.layers, &(&1.name == name))

  defp decode(text) do
    case JSON.decode(text) do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, {:ldtk, reason}}
    end
  end

  defp project(raw, load) do
    {:ok,
     %{
       grid_size: raw["defaultGridSize"],
       levels: Enum.map(raw["levels"] || [], &level(full(&1, load)))
     }}
  rescue
    error -> {:error, {:ldtk, Exception.message(error)}}
  end

  defp full(%{"layerInstances" => nil, "externalRelPath" => file}, load) when is_binary(file),
    do: load.(file)

  defp full(raw, _load), do: raw

  defp read_level(path) do
    with {:ok, text} <- File.read(path),
         {:ok, raw} <- decode(text) do
      raw
    else
      {:error, reason} -> raise ArgumentError, "level file #{path}: #{inspect(reason)}"
    end
  end

  defp level(raw),
    do: %{
      name: raw["identifier"],
      x: raw["worldX"],
      y: raw["worldY"],
      width: raw["pxWid"],
      height: raw["pxHei"],
      fields: fields(raw["fieldInstances"]),
      layers: Enum.map(raw["layerInstances"] || [], &layer/1)
    }

  defp layer(raw) do
    base = %{
      name: raw["__identifier"],
      columns: raw["__cWid"],
      rows: raw["__cHei"],
      grid_size: raw["__gridSize"],
      visible?: raw["visible"] != false
    }

    Map.merge(base, contents(raw["__type"], raw))
  end

  defp contents("IntGrid", raw) do
    tiles = contents("Tiles", raw)

    values =
      for {value, index} <- Enum.with_index(raw["intGridCsv"] || []),
          value != 0,
          into: %{},
          do: {cell(index, raw["__cWid"]), value}

    Map.merge(
      %{kind: :int_grid, values: values},
      if(tiles.tiles == [], do: %{}, else: %{tiles: tiles.tiles})
    )
  end

  defp contents("Entities", raw) do
    grid = raw["__gridSize"]
    %{kind: :entities, entities: Enum.map(raw["entityInstances"] || [], &entity(&1, grid))}
  end

  defp contents(_tiles, raw) do
    grid = raw["__gridSize"]
    placed = (raw["gridTiles"] || []) ++ (raw["autoLayerTiles"] || [])
    %{kind: :tiles, tiles: Enum.map(placed, &tile(&1, grid))}
  end

  defp tile(%{"px" => [px, py]} = raw, grid),
    do: %{at: {div(px, grid), div(py, grid)}, tile: raw["t"], flips: flips(raw["f"] || 0)}

  defp flips(0), do: []
  defp flips(1), do: [:horizontal]
  defp flips(2), do: [:vertical]
  defp flips(3), do: [:horizontal, :vertical]

  defp entity(raw, grid) do
    [px, py] = raw["px"]

    %{
      id: raw["iid"],
      name: raw["__identifier"],
      x: px / grid,
      y: py / grid,
      width: (raw["width"] || grid) / grid,
      height: (raw["height"] || grid) / grid,
      fields: fields(raw["fieldInstances"])
    }
  end

  defp cell(index, columns), do: {rem(index, columns), div(index, columns)}

  defp fields(nil), do: %{}
  defp fields(list), do: Map.new(list, &{&1["__identifier"], &1["__value"]})
end
