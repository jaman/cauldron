defmodule Cauldron2D.Minimap do
  @moduledoc """
  The whole map in a few rows of braille: walls in one colour, marks — players, bases,
  goals — over them, each a dot or a two-by-two.

      Cauldron2D.Minimap.rows(
        size: {width, height},
        solid?: &MyGame.wall?/1,
        cells: {30, 12},
        marks: [{me.pos, {255, 220, 0}, 2}, {enemy.pos, {255, 90, 90}, 2}],
        key: {:my_game, map_name}
      )

  Each row is a list of `{text, colour}` runs to lay side by side, in the shape a hud row
  takes. A braille cell holds two columns and four rows of the map scaled to fit. Where
  marks meet, the earlier in the list shows.

  ## Options

    * `:size` — `{width, height}` of the map in tiles. Required
    * `:solid?` — a function from a tile to whether it is drawn as wall. Required
    * `:cells` — `{columns, rows}` of the minimap. Required
    * `:marks` — `[{{x, y}, colour, 1 | 2}]` in tiles. Default `[]`
    * `:wall`, `:empty` — the colours of walls and of cells with nothing.
      Defaults `{70, 100, 230}` and `{40, 40, 60}`
    * `:key` — under which the scaled walls and the drawn cells are kept for later calls
      with the same cells and colours, in `:persistent_term`, so a call draws only the
      cells its marks touch. Default: none, drawn whole every call
  """

  import Bitwise

  @type rgb :: {byte(), byte(), byte()}
  @type run :: {String.t(), rgb()}
  @type mark :: {{number(), number()}, rgb(), 1 | 2}

  @wall {70, 100, 230}
  @empty {40, 40, 60}

  @doc "The minimap as rows of runs; see the module documentation for the options."
  @spec rows(keyword()) :: [[run()]]
  def rows(opts) do
    {width, height} = Keyword.fetch!(opts, :size)
    {columns, rows} = Keyword.fetch!(opts, :cells)
    dots = {columns * 2, rows * 4}
    scale = min(elem(dots, 0) / width, elem(dots, 1) / height)
    key = Keyword.get(opts, :key)
    walls = walls(key, Keyword.fetch!(opts, :solid?), scale, {width, height}, dots)
    marks = marks(Keyword.get(opts, :marks, []), scale)
    wall = Keyword.get(opts, :wall, @wall)
    empty = Keyword.get(opts, :empty, @empty)
    base = base(key, walls, {columns, rows}, wall, empty)

    touched =
      marks
      |> Map.keys()
      |> Enum.map(fn {x, y} -> {div(x, 2), div(y, 4)} end)
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))

    for row <- 0..(rows - 1) do
      case Map.get(touched, row) do
        nil ->
          elem(base, row) |> elem(1)

        touched_columns ->
          redrawn(elem(base, row), row, MapSet.new(touched_columns), walls, marks, wall, empty)
      end
    end
  end

  defp redrawn({cells, _runs}, row, drawn, walls, marks, wall, empty) do
    cells
    |> Enum.with_index()
    |> Enum.map(fn {kept, column} ->
      if MapSet.member?(drawn, column),
        do: cell({column, row}, walls, marks, wall, empty),
        else: kept
    end)
    |> runs()
  end

  defp base(nil, walls, cells, wall, empty), do: drawn_base(walls, cells, wall, empty)

  defp base(key, walls, cells, wall, empty) do
    term = {__MODULE__, key, cells, wall, empty}

    case :persistent_term.get(term, nil) do
      nil ->
        base = drawn_base(walls, cells, wall, empty)
        :persistent_term.put(term, base)
        base

      base ->
        base
    end
  end

  defp drawn_base(walls, {columns, rows}, wall, empty) do
    for row <- 0..(rows - 1) do
      cells = for column <- 0..(columns - 1), do: cell({column, row}, walls, %{}, wall, empty)
      {cells, runs(cells)}
    end
    |> List.to_tuple()
  end

  defp walls(nil, solid?, scale, size, dots), do: scaled_walls(solid?, scale, size, dots)

  defp walls(key, solid?, scale, size, dots) do
    term = {__MODULE__, key, dots}

    case :persistent_term.get(term, nil) do
      nil ->
        walls = scaled_walls(solid?, scale, size, dots)
        :persistent_term.put(term, walls)
        walls

      walls ->
        walls
    end
  end

  defp scaled_walls(solid?, scale, {width, height}, {across, down}) do
    for x <- 0..(width - 1), y <- 0..(height - 1), solid?.({x, y}), reduce: MapSet.new() do
      acc -> MapSet.put(acc, {min(across - 1, trunc(x * scale)), min(down - 1, trunc(y * scale))})
    end
  end

  defp marks(marks, scale) do
    marks
    |> Enum.with_index()
    |> Enum.flat_map(fn {mark, order} -> dots(mark, order, scale) end)
    |> Enum.reduce(%{}, fn {dot, mark}, acc -> Map.update(acc, dot, mark, &earlier(&1, mark)) end)
  end

  defp dots({{x, y}, colour, 1}, order, scale),
    do: [{{trunc(x * scale), trunc(y * scale)}, {order, colour}}]

  defp dots({{x, y}, colour, 2}, order, scale) do
    dx = trunc(x * scale)
    dy = trunc(y * scale)
    for ox <- 0..1, oy <- 0..1, do: {{dx - 1 + ox, dy - 1 + oy}, {order, colour}}
  end

  defp earlier({order, _} = kept, {later, _}) when order < later, do: kept
  defp earlier(_kept, mark), do: mark

  defp cell({column, row}, walls, marks, wall, empty) do
    dots = for dy <- 0..3, dx <- 0..1, do: {column * 2 + dx, row * 4 + dy}
    marked = dots |> Enum.map(&Map.get(marks, &1)) |> Enum.reject(&is_nil/1)

    bits =
      Enum.reduce(Enum.with_index(dots), 0, fn {dot, index}, acc ->
        if MapSet.member?(walls, dot) or Map.has_key?(marks, dot),
          do: acc ||| bit(index),
          else: acc
      end)

    colour =
      cond do
        marked != [] -> marked |> Enum.min() |> elem(1)
        bits != 0 -> wall
        true -> empty
      end

    {<<0x2800 + bits::utf8>>, colour}
  end

  defp bit(index) do
    {dx, dy} = {rem(index, 2), div(index, 2)}
    Enum.at([1, 2, 4, 64, 8, 16, 32, 128], dx * 4 + dy)
  end

  defp runs(cells) do
    cells
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn chunk -> {Enum.map_join(chunk, &elem(&1, 0)), elem(hd(chunk), 1)} end)
  end
end
