defmodule Town.Legend do
  @moduledoc """
  The town as a map of cells, read from `priv/town.txt`: one character a tile.

      .  grass       =  road        ,  cobbles      ~  water       :  dirt
      T  tree        P  pine        l  lamp         o  barrel
      h H  plaster house, one or two storeys       b B  brick house
      s S  shop                                    w K  stone wall, keep (three storeys)

  Every building's ground storey gets a door on the side nearest a road, cobbles or
  dirt; a stone wall (`w`) has none. `install/0` builds the town once and keeps it
  under `:persistent_term`; `cell/1` is what `Cauldron2D` draws at a tile,
  `walkable?/1` whether a mover may stand on it, and `size/0` the town's extent.
  """

  @type position :: {integer(), integer()}

  @floors %{"." => :grass, "=" => :road, "," => :cobble, "~" => :water, ":" => :dirt}
  @props %{
    "T" => {:grass, :tree},
    "P" => {:grass, :pine},
    "l" => {:cobble, :lamp},
    "o" => {:cobble, :barrel}
  }
  @blocks %{
    "h" => {:plaster, 1},
    "H" => {:plaster, 2},
    "b" => {:brick, 1},
    "B" => {:brick, 2},
    "s" => {:shop, 1},
    "S" => {:shop, 2},
    "w" => {:stone, 1},
    "K" => {:stone, 3}
  }
  @doorless ["w"]
  @walkable [:grass, :road, :cobble, :dirt]
  @roadish [:road, :cobble, :dirt]
  @sides [n: {0, -1}, e: {1, 0}, s: {0, 1}, w: {-1, 0}]
  @key {__MODULE__, :town}

  @doc "Build the town from the legend file and keep it for `cell/1`; returns its size."
  @spec install() :: {pos_integer(), pos_integer()}
  def install do
    town = build(File.read!(Path.join(:code.priv_dir(:town), "town.txt")))
    :persistent_term.put(@key, town)
    town.size
  end

  @doc "The town's size in tiles."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: town().size

  @doc "What is at a tile, as `Cauldron2D.Surface` takes a cell; `:void` beyond the town."
  @spec cell(position()) :: Cauldron2D.Surface.cell()
  def cell(position), do: Map.get(town().cells, position, :void)

  @doc "Whether a mover may stand at a world point."
  @spec walkable?({number(), number()}) :: boolean()
  def walkable?({x, y}), do: MapSet.member?(town().walkable, {floor(x), floor(y)})

  @doc "The tiles a mover may stand on that are paved: road, cobbles or dirt."
  @spec paved() :: [position()]
  def paved, do: town().paved

  @doc "The town the legend text describes, for tests; `install/0` keeps one for the game."
  @spec build(String.t()) :: %{
          size: {pos_integer(), pos_integer()},
          cells: map(),
          walkable: MapSet.t(),
          paved: [position()]
        }
  def build(text) do
    rows = text |> String.split("\n", trim: true) |> Enum.map(&String.graphemes/1)
    width = rows |> hd() |> length()

    chars =
      for {row, y} <- Enum.with_index(rows),
          {char, x} <- Enum.with_index(row),
          into: %{},
          do: {{x, y}, char}

    doors = doors(chars)

    cells =
      Map.new(chars, fn {position, char} -> {position, cell(char, Map.get(doors, position))} end)

    open = for {position, char} <- chars, walkable_char?(char), do: position
    paved = for {position, char} <- chars, Map.get(@floors, char) in @roadish, do: position

    %{size: {width, length(rows)}, cells: cells, walkable: MapSet.new(open), paved: paved}
  end

  defp town, do: :persistent_term.get(@key)

  defp walkable_char?(char), do: Map.get(@floors, char) in @walkable

  defp cell(char, door) do
    cond do
      Map.has_key?(@floors, char) ->
        {Map.fetch!(@floors, char), [], nil}

      Map.has_key?(@props, char) ->
        props_cell(Map.fetch!(@props, char))

      Map.has_key?(@blocks, char) ->
        block_cell(Map.fetch!(@blocks, char), char in @doorless, door)
    end
  end

  defp props_cell({floor, prop}), do: {floor, [prop], nil}

  defp block_cell({:stone, 1}, true, _door), do: {:cobble, [:stone_wall], nil}

  defp block_cell({material, storeys}, _doorless, door) do
    ground = if door, do: :"#{material}_ground_#{door}", else: :"#{material}_ground"
    upper = List.duplicate(:"#{material}_upper", storeys - 1)
    {:cobble, [ground | upper], nil}
  end

  defp doors(chars) do
    roadish = for {position, char} <- chars, Map.get(@floors, char) in @roadish, do: position

    chars
    |> Enum.filter(fn {_position, char} ->
      Map.has_key?(@blocks, char) and char not in @doorless
    end)
    |> Enum.map(&elem(&1, 0))
    |> buildings(chars)
    |> Enum.flat_map(fn building ->
      case nearest_door(building, roadish) do
        nil -> []
        {position, side} -> [{position, side}]
      end
    end)
    |> Map.new()
  end

  defp buildings(positions, chars), do: buildings(MapSet.new(positions), chars, [])

  defp buildings(pending, chars, found) do
    case Enum.min(pending, fn -> nil end) do
      nil -> found
      seed -> flood(seed, pending, chars, found)
    end
  end

  defp flood(seed, pending, chars, found) do
    {building, rest} =
      grow([seed], MapSet.delete(pending, seed), MapSet.new([seed]), chars[seed], chars)

    buildings(rest, chars, [MapSet.to_list(building) | found])
  end

  defp grow([], pending, building, _char, _chars), do: {building, pending}

  defp grow([{x, y} | queue], pending, building, char, chars) do
    neighbours =
      for {_side, {dx, dy}} <- @sides,
          position = {x + dx, y + dy},
          MapSet.member?(pending, position),
          chars[position] == char,
          do: position

    grow(
      queue ++ neighbours,
      Enum.reduce(neighbours, pending, &MapSet.delete(&2, &1)),
      Enum.reduce(neighbours, building, &MapSet.put(&2, &1)),
      char,
      chars
    )
  end

  defp nearest_door(building, roadish) do
    for {bx, by} <- building, {rx, ry} <- roadish do
      {abs(rx - bx) + abs(ry - by), {bx, by}, {rx - bx, ry - by}}
    end
    |> Enum.min(fn -> nil end)
    |> case do
      nil -> nil
      {_distance, position, delta} -> {position, side_of(delta)}
    end
  end

  defp side_of({dx, dy}) when abs(dx) > abs(dy), do: if(dx > 0, do: :e, else: :w)
  defp side_of({_dx, dy}), do: if(dy >= 0, do: :s, else: :n)
end
