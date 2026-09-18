defmodule Cauldron2D.Camera do
  @moduledoc """
  Resolves which part of a world is on screen.

      Cauldron2D.Camera.view(
        focus: {x, y},
        size: {columns, rows},
        cell: fn {x, y} -> cell end
      )

  `:cell` is called exactly once per visible tile, with that tile's world coordinate, and
  returns a `t:Cauldron2D.Surface.cell/0`. It is the only thing the engine asks of a game.

  The viewport is always centred on `:focus`: at a world's edge, or zoomed out past it, the
  coordinates asked for run outside the world and `:cell` answers for them (`:void`, or a
  wrapped tile) — the focus never moves off the centre to keep the world on screen.

  A tile occupies two terminal cells across and one down. `columns_for/1` and `rows_for/1`
  convert a pane's size in cells into a viewport size in tiles; `zoomed/2` scales that
  size for a zoom — how many times larger than native a tile is drawn — and `tile_at/3`
  and `zoom_about/6` map cells back through it. A `:size` may be fractional: the origin
  centres the focus exactly, and the tiles read cover the fraction.
  """

  alias Cauldron2D.{Atlas, Surface}

  @type point :: {integer(), integer()}

  @type t :: %__MODULE__{
          origin: point(),
          scroll: {float(), float()},
          columns: pos_integer(),
          rows: pos_integer(),
          cells: [[Surface.cell()]]
        }

  defstruct [:origin, :columns, :rows, :cells, scroll: {0.0, 0.0}]

  @doc """
  Resolve the viewport and read every tile in it.

  Returns a `t:t/0` whose `:cells` is a list of `rows` rows, each of `columns` cells, in
  top-to-bottom and left-to-right order, and whose `:origin` is the world coordinate of the
  top-left tile.

  ## Options

    * `:focus` — the `{x, y}` world point to centre on, required
    * `:size` — `{columns, rows}` in tiles, required, both positive, whole or not
    * `:cell` — `fn {x, y} -> cell end`, required
    * `:scroll` — `true` to keep the focus at the exact centre: `:origin` is then the
      exact origin rounded down, `:cells` holds one more column and one more row than
      `:size`, and `:scroll` is the fraction of a tile, `{0.0..1.0, 0.0..1.0}`, the cells
      are to be shifted left and up by. Default `false`: `:origin` is `origin/3`, `:cells`
      is exactly `:size`, `:scroll` is `{0.0, 0.0}`
  """
  @spec view(keyword()) :: t()
  def view(opts) do
    {width, height} = Keyword.fetch!(opts, :size)
    {columns, rows} = {ceil(width), ceil(height)}
    cell = Keyword.fetch!(opts, :cell)
    focus = Keyword.fetch!(opts, :focus)

    {origin, scroll, extra} =
      if Keyword.get(opts, :scroll, false) do
        {ex, ey} = exact_origin(focus, {width, height})
        floored = {floor(ex), floor(ey)}
        {floored, {ex - floor(ex), ey - floor(ey)}, 1}
      else
        {origin(focus, {columns, rows}), {0.0, 0.0}, 0}
      end

    cells =
      for row <- 0..(rows - 1 + extra)//1 do
        for column <- 0..(columns - 1 + extra)//1 do
          cell.(offset(origin, column, row))
        end
      end

    %__MODULE__{origin: origin, scroll: scroll, columns: columns, rows: rows, cells: cells}
  end

  @doc """
  Where a viewport `size` tiles across sits in world coordinates when `focus` is at its
  exact centre, as floats.

  """
  @spec exact_origin({number(), number()}, {number(), number()}) :: {float(), float()}
  def exact_origin({fx, fy}, {columns, rows}), do: {fx - columns / 2, fy - rows / 2}

  defp offset({ox, oy}, column, row), do: {ox + column, oy + row}

  @doc """
  Where a viewport `size` tiles across sits in world coordinates when centred on `focus`.

  This is the `:origin` `view/1` produces for the same arguments, so a caller mapping a screen
  position back to the world resolves against the same tiles that were drawn.

  A fractional focus is rounded to the nearest tile first.
  """
  @spec origin(point(), {pos_integer(), pos_integer()}) :: point()
  def origin({fx, fy}, {columns, rows}),
    do: {round(fx) - div(columns, 2), round(fy) - div(rows, 2)}

  @doc """
  The view as glyphs and colours, for renderers that draw characters.

  Each cell becomes `{glyph, {r, g, b}}` with the tint already applied, in the same row and
  column order as `:cells`. A cell with overlays takes the glyph and colour of its topmost
  overlay; `:void` becomes two spaces in the atlas's void colour.
  """
  @spec glyphs(Atlas.name() | Atlas.t(), t()) :: [[{String.t(), Atlas.rgb()}]]
  def glyphs(atlas, %__MODULE__{cells: cells}) do
    atlas = Atlas.fetch(atlas)
    Enum.map(cells, fn row -> Enum.map(row, &glyph(atlas, &1)) end)
  end

  defp glyph(atlas, :void), do: {"  ", atlas.void}

  defp glyph(atlas, {base, [], tint}) do
    entry = Atlas.entry(atlas, base)
    {entry.glyph, Surface.shade_color(atlas, entry.color, tint)}
  end

  defp glyph(atlas, {_base, overlays, tint}) do
    entry = Atlas.entry(atlas, List.last(overlays))
    {entry.glyph, Surface.shade_color(atlas, entry.color, tint)}
  end

  @doc """
  The world tile under `{column, row}`, given in terminal cells relative to the pane's
  top-left corner, for a viewport whose origin is the first argument.

  The result is fractional and resolves to the centre of the cell, so `trunc/1` on either
  coordinate gives the whole tile the cell belongs to. The column is halved, since a tile is
  two cells wide: cells 0 and 1 both fall in tile 0, at 0.25 and 0.75.

  Pair with `origin/3` to map a pointer position back to the world it is over.
  """
  @spec tile_at(point(), {number(), number()}) :: {float(), float()}
  def tile_at({ox, oy}, {column, row}), do: {ox + (column + 0.5) / 2, oy + row + 0.5}

  @doc "`tile_at/2` through a zoom: a tile drawn `zoom` times its native size spans `2 * zoom` cells across and `zoom` down."
  @spec tile_at({number(), number()}, {number(), number()}, number()) :: {float(), float()}
  def tile_at({ox, oy}, {column, row}, zoom),
    do: {ox + (column + 0.5) / (2 * zoom), oy + (row + 0.5) / zoom}

  @doc "The viewport in tiles of a pane `size` tiles across at native size, drawn at `zoom`."
  @spec zoomed({number(), number()}, number()) :: {float(), float()}
  def zoomed({columns, rows}, zoom), do: {columns / zoom, rows / zoom}

  @doc """
  The focus that keeps the world under `cell` where it is on screen when a pane of native
  `size` goes from `from` to `to` zoom, centred on `focus` before. Zooming back the same
  way about the same cell returns to the focus it started from.
  """
  @spec zoom_about(
          {number(), number()},
          {number(), number()},
          {number(), number()},
          number(),
          number()
        ) :: {float(), float()}
  def zoom_about(focus, cell, size, from, to) do
    {wx, wy} = tile_at(exact_origin(focus, zoomed(size, from)), cell, from)
    {ox, oy} = tile_at({0.0, 0.0}, cell, to)
    {columns, rows} = zoomed(size, to)
    {wx - ox + columns / 2, wy - oy + rows / 2}
  end

  @doc "How many tiles wide a pane `width` terminal cells across can show; always at least 1."
  @spec columns_for(non_neg_integer()) :: pos_integer()
  def columns_for(width), do: max(1, div(max(width, 1), 2))

  @doc "How many tiles tall a pane `height` terminal cells high can show; always at least 1."
  @spec rows_for(non_neg_integer()) :: pos_integer()
  def rows_for(height), do: max(1, height)
end
