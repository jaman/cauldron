defmodule Parade.Legend do
  @moduledoc """
  The courtyard as a grid of cells, read from `priv/parade.txt`.

      .  stone      ,  grass      :  dirt      "  moss
      W  wall       P  pillar

  `install/0` reads the file and keeps the courtyard for `cell/1`; `size/0` is its extent
  in tiles and `walkable?/1` whether a mover may stand at a world point.
  """

  @type position :: {integer(), integer()}

  @floors %{"." => :stone, "," => :grass, ":" => :dirt, "\"" => :moss}
  @blocks %{"W" => {:wall, 1}, "P" => {:pillar, 2}}
  @key {__MODULE__, :parade}

  @doc "Build the courtyard from the map file and keep it for `cell/1`; returns its size."
  @spec install() :: {pos_integer(), pos_integer()}
  def install do
    courtyard = build(File.read!(Path.join(:code.priv_dir(:parade), "parade.txt")))
    :persistent_term.put(@key, courtyard)
    courtyard.size
  end

  @doc "The courtyard's size in tiles."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: courtyard().size

  @doc "What is at a tile, as `Cauldron2D.Surface` takes a cell; `:void` beyond the courtyard."
  @spec cell(position()) :: Cauldron2D.Surface.cell()
  def cell(position), do: Map.get(courtyard().cells, position, :void)

  @doc "Whether a mover may stand at a world point."
  @spec walkable?({number(), number()}) :: boolean()
  def walkable?({x, y}), do: MapSet.member?(courtyard().walkable, {floor(x), floor(y)})

  @doc "The tiles a mover may stand on."
  @spec open() :: [position()]
  def open, do: courtyard().open

  @doc "The courtyard the map text describes, for tests; `install/0` keeps one for the game."
  @spec build(String.t()) :: %{
          size: {pos_integer(), pos_integer()},
          cells: map(),
          walkable: MapSet.t(),
          open: [position()]
        }
  def build(text) do
    rows = text |> String.split("\n", trim: true) |> Enum.map(&String.graphemes/1)
    width = rows |> hd() |> length()

    chars =
      for {row, y} <- Enum.with_index(rows),
          {char, x} <- Enum.with_index(row),
          into: %{},
          do: {{x, y}, char}

    cells = Map.new(chars, fn {position, char} -> {position, cell_for(char)} end)
    open = for {position, char} <- chars, Map.has_key?(@floors, char), do: position

    %{size: {width, length(rows)}, cells: cells, walkable: MapSet.new(open), open: open}
  end

  defp courtyard, do: :persistent_term.get(@key)

  defp cell_for(char) when is_map_key(@floors, char), do: {Map.fetch!(@floors, char), [], nil}

  defp cell_for(char) do
    {block, storeys} = Map.fetch!(@blocks, char)
    {:stone, List.duplicate(block, storeys), nil}
  end
end
