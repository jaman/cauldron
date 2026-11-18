defmodule Beast.Region do
  @moduledoc """
  One region of the beast's world, read from its map in `priv/maps` (a `Cauldron2D.Map`):
  its rock, platforms and spikes, its locked doors and their key, the healing fruit,
  the standing stones that keep the beast's place, where the beast starts, the creatures
  and where they wait, the arena's gates and its boss, and the way on.

  The legend: `#` rock, `=` a platform (stood on from above), `^` spikes, `D` a locked
  door, `k` the key that opens every door of the region, `h` healing fruit, `C` a
  standing stone, `S` the start, `X` the way on (open once the boss is beaten), `G` the
  arena's gates (shut while the boss lives and the beast is inside), `B` the boss, and
  for creatures `c` a crawler, `b` a bat, `g` a goblin, `a` an archer.
  """

  alias Cauldron2D.Map, as: TileMap

  @creatures %{"c" => :crawler, "b" => :bat, "g" => :goblin, "a" => :archer}

  @regions [
    %{
      id: :plain,
      file: "plain.txt",
      outdoor?: true,
      boss: :wyrm,
      rock: :rock_plain,
      backdrop: :plain
    },
    %{
      id: :caverns,
      file: "caverns.txt",
      outdoor?: false,
      boss: :troll,
      rock: :rock_caverns,
      backdrop: :caverns
    },
    %{
      id: :tree,
      file: "tree.txt",
      outdoor?: true,
      boss: :spirit,
      rock: :rock_tree,
      backdrop: :tree
    },
    %{
      id: :castle,
      file: "castle.txt",
      outdoor?: false,
      boss: :mage,
      rock: :rock_castle,
      backdrop: :castle
    }
  ]

  @type t :: map()

  @doc "How many regions there are."
  @spec count() :: pos_integer()
  def count, do: length(@regions)

  @doc "Region `number`, from `1`, read from its map."
  @spec load(pos_integer()) :: t()
  def load(number) do
    entry = Enum.at(@regions, number - 1)
    {:ok, map} = TileMap.parse_file(Path.join([:code.priv_dir(:beast), "maps", entry.file]))

    Map.merge(entry, %{
      number: number,
      name: TileMap.option(map, "name", :string, "THE WILD"),
      width: map.width,
      height: map.height,
      tiles: tiles(map),
      start: first(map, "S"),
      exit: first(map, "X"),
      boss_at: first(map, "B"),
      gates: TileMap.positions(map, "G"),
      doors: TileMap.positions(map, "D"),
      keys: TileMap.positions(map, "k"),
      fruit: TileMap.positions(map, "h"),
      stones: TileMap.positions(map, "C"),
      creatures:
        for({char, kind} <- @creatures, at <- TileMap.positions(map, char), do: {kind, at})
    })
  end

  @doc """
  What is at a tile for a body moving through it — `:solid`, `:platform` or `:open` —
  with the doors shut unless `open_doors?` and the gates shut while `gated?`. Spikes are
  solid: they are stood on, and hurt.
  """
  @spec grid(t(), boolean(), boolean()) :: ({integer(), integer()} -> :solid | :platform | :open)
  def grid(region, open_doors?, gated?) do
    doors = if open_doors?, do: MapSet.new(), else: MapSet.new(region.doors)
    gates = if gated?, do: MapSet.new(region.gates), else: MapSet.new()

    fn {x, _y} = at ->
      cond do
        x < 0 or x >= region.width -> :solid
        MapSet.member?(doors, at) or MapSet.member?(gates, at) -> :solid
        true -> region.tiles |> Map.get(at, :open) |> solid()
      end
    end
  end

  @doc "What is drawn at a tile: `:rock`, `:platform`, `:spikes` or `nil`."
  @spec tile(t(), {integer(), integer()}) :: :rock | :platform | :spikes | nil
  def tile(region, at), do: Map.get(region.tiles, at)

  @doc "Whether the beast's box touches spikes."
  @spec spikes?(t(), [{integer(), integer()}]) :: boolean()
  def spikes?(region, tiles), do: Enum.any?(tiles, &(Map.get(region.tiles, &1) == :spikes))

  @doc "The x of the arena's gates: the beast is in the arena past it."
  @spec arena(t()) :: number()
  def arena(%{gates: [{x, _y} | _]}), do: x
  def arena(region), do: region.width

  defp solid(:rock), do: :solid
  defp solid(:spikes), do: :solid
  defp solid(:platform), do: :platform
  defp solid(_other), do: :open

  defp tiles(map) do
    map
    |> TileMap.cells(fn
      "#" -> :rock
      "=" -> :platform
      "^" -> :spikes
      _other -> nil
    end)
    |> Map.reject(fn {_at, tile} -> tile == nil end)
  end

  defp first(map, char) do
    case TileMap.positions(map, char) do
      [at | _] -> at
      [] -> nil
    end
  end
end
