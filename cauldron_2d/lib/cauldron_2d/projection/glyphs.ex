defmodule Cauldron2D.Projection.Glyphs do
  @moduledoc """
  A projection drawn as one of the atlas's two-character glyphs per slot.

      Cauldron2D.Projection.Glyphs.compose(:my_game, Cauldron2D.Projection.Iso,
        focus: {12.5, 8.5},
        cell: &MyGame.cell/1,
        size: {320, 200},
        step: {32, 32},
        facing: 1,
        facings: 4
      )

  `module` must answer `ground_map/2`: `Cauldron2D.Projection.Iso` or
  `Cauldron2D.Projection.Oblique`. Every option except `:step` is that projection's own,
  and `:size` is the picture in pixels it would draw.

  `:step` is `{across, down}`, the pixels of that picture one slot covers, so the grid is
  `div(width, across)` slots wide and `div(height, down)` tall. A slot takes the glyph and
  colour of the cell at the world point the projection shows at its middle, the last
  standing art where a cell has any, as `Cauldron2D.Camera.glyphs/2` chooses them. Movers
  and labels are drawn over that, each at the slot it projects into.

  Returns rows of `{glyph, colour}`.
  """

  alias Cauldron2D.{Atlas, Surface}
  alias Cauldron2D.Projection.Volume

  @type slot :: {String.t(), {byte(), byte(), byte()}}

  @doc "The grid, as the module documentation describes."
  @spec compose(Atlas.name() | Atlas.t(), module(), keyword()) :: [[slot()]]
  def compose(atlas, module, opts) do
    atlas = Atlas.fetch(atlas)
    {width, height} = Keyword.fetch!(opts, :size)
    {across, down} = Keyword.fetch!(opts, :step)
    cell = Keyword.fetch!(opts, :cell)
    walk = module.ground_map(atlas, opts)

    columns = max(1, div(width, across))
    rows = max(1, div(height, down))
    volumes = Volume.list(Keyword.get(opts, :volumes, []))

    for row <- 0..(rows - 1) do
      for column <- 0..(columns - 1) do
        at = world(walk, {(column + 0.5) * across, (row + 0.5) * down})

        at
        |> tile()
        |> cell.()
        |> glyph(atlas)
        |> seen_through(volumes, at)
      end
    end
    |> over(atlas, walk, opts, {across, down}, {columns, rows})
  end

  defp world({{ox, oy}, {rx, ry}, {dx, dy}}, {px, py}),
    do: {ox + px * rx + py * dx, oy + px * ry + py * dy}

  defp tile({x, y}), do: {floor(x), floor(y)}

  defp glyph(:void, atlas), do: {"  ", atlas.void}

  defp glyph({base, [], tint}, atlas), do: shown(atlas, base, tint)
  defp glyph({_base, overlays, tint}, atlas), do: shown(atlas, List.last(overlays), tint)

  defp seen_through(slot, [], _at), do: slot

  defp seen_through({glyph, colour}, volumes, {wx, wy}) do
    tinted =
      Enum.reduce(volumes, colour, fn volume, {red, green, blue} ->
        through = Volume.through(volume, {wx, wy, 0.0}, {0.0, 0.0, 1.0}, :infinity)
        <<tr, tg, tb, _alpha>> = Volume.mix(<<red, green, blue, 255>>, volume, through)
        {tr, tg, tb}
      end)

    {glyph, tinted}
  end

  defp shown(atlas, art, tint) do
    entry = Atlas.entry(atlas, art)
    {entry.glyph, Surface.shade_color(atlas, entry.color, tint)}
  end

  defp over(grid, atlas, walk, opts, step, size) do
    grid
    |> movers(atlas, walk, opts, step, size)
    |> labels(walk, opts, step, size)
  end

  defp movers(grid, atlas, walk, opts, step, size) do
    opts
    |> Keyword.get(:movers, [])
    |> Enum.reduce(grid, fn mover, acc ->
      {art, position} = walker(mover)
      entry = Atlas.entry(atlas, art)

      put(acc, slot(walk, position, step), size, {entry.glyph, entry.color})
    end)
  end

  defp walker({art, position}), do: {art, position}
  defp walker({art, position, _heading}), do: {art, position}
  defp walker({art, position, _tint, _pose, _flip}), do: {art, position}

  defp labels(grid, walk, opts, step, size) do
    opts
    |> Keyword.get(:labels, [])
    |> Enum.reduce(grid, fn label, acc ->
      {text, position, colour} = named(label)
      {column, row} = slot(walk, position, step)

      text
      |> String.graphemes()
      |> Enum.chunk_every(2)
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {pair, index}, rows ->
        put(
          rows,
          {column + index, row},
          size,
          {Enum.join(pair) |> String.pad_trailing(2), colour}
        )
      end)
    end)
  end

  defp named({text, position, colour}), do: {text, position, colour}
  defp named({text, position, colour, _opts}), do: {text, position, colour}

  defp slot({{ox, oy}, {rx, ry}, {dx, dy}}, {wx, wy}, {across, down}) do
    {ax, ay} = {wx - ox, wy - oy}
    det = rx * dy - dx * ry
    {floor((ax * dy - dx * ay) / det / across), floor((rx * ay - ax * ry) / det / down)}
  end

  defp put(grid, {column, row}, {columns, rows}, drawn)
       when column >= 0 and column < columns and row >= 0 and row < rows,
       do: List.update_at(grid, row, &List.replace_at(&1, column, drawn))

  defp put(grid, _slot, _size, _drawn), do: grid
end
