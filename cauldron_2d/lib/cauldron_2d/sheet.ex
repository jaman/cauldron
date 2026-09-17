defmodule Cauldron2D.Sheet do
  @moduledoc """
  A `Cauldron2D.Atlas` packed onto one raster, with an index of where every art is.

      sheet = Cauldron2D.Sheet.pack(:my_game)
      Cauldron2D.Sheet.index(sheet, "/atlas.png")

  Every frame of every art is a tile on the sheet, laid out in rows of `columns/0`;
  index 0 is left empty for "nothing here", so arts count from 1. `arts` maps each art
  name to the index of its first frame, `frames` gives each index's pixel position on the
  sheet, and `anim` maps the first index of each animated art to its indices and rate.
  `index_at/3` is the index showing at a time. An art may be any term the atlas keys it
  by; in the wire form it is named by `inspect/1` unless it is an atom.
  """

  alias Cauldron2D.Atlas
  alias FrenchCurve.Raster

  @columns 16

  @type t :: %{
          tile: pos_integer(),
          columns: pos_integer(),
          rows: pos_integer(),
          arts: %{Atlas.art() => pos_integer()},
          frames: [[non_neg_integer()]],
          anim: %{pos_integer() => %{indices: [pos_integer()], fps: pos_integer()}},
          raster: Raster.t(),
          void: Atlas.rgb()
        }

  @doc "How many tiles wide a sheet is."
  @spec columns() :: pos_integer()
  def columns, do: @columns

  @doc "Lay every frame of every art of `atlas` out on one raster."
  @spec pack(Atlas.t() | Atlas.name()) :: t()
  def pack(atlas) do
    atlas = Atlas.fetch(atlas)
    names = atlas.entries |> Map.keys() |> Enum.sort()
    {slots, count} = slots(atlas, names)
    rows = div(count + @columns - 1, @columns)

    frames =
      for index <- 0..(count - 1),
          do: [rem(index, @columns) * atlas.tile, div(index, @columns) * atlas.tile]

    %{
      tile: atlas.tile,
      columns: @columns,
      rows: rows,
      arts: Map.new(slots, fn {name, first, _frames, _fps} -> {name, first} end),
      frames: frames,
      anim:
        for(
          {_name, first, indices, fps} <- slots,
          length(indices) > 1,
          into: %{},
          do: {first, %{indices: indices, fps: fps}}
        ),
      raster: paint(atlas, slots, rows),
      void: atlas.void
    }
  end

  defp slots(atlas, names) do
    Enum.map_reduce(names, 1, fn name, next ->
      entry = Atlas.entry(atlas, name)
      count = length(entry.frames)
      {{name, next, Enum.to_list(next..(next + count - 1)), entry.fps}, next + count}
    end)
  end

  defp paint(atlas, slots, rows) do
    canvas = Raster.new(@columns * atlas.tile, rows * atlas.tile, background: {0, 0, 0, 0})

    for {name, _first, indices, _fps} <- slots,
        {index, sprite} <- Enum.zip(indices, Atlas.entry(atlas, name).frames),
        reduce: canvas do
      canvas ->
        blit(
          canvas,
          sprite.raster,
          rem(index, @columns) * atlas.tile,
          div(index, @columns) * atlas.tile,
          atlas.tile
        )
    end
  end

  defp blit(canvas, raster, left, top, tile) do
    for x <- 0..(tile - 1), y <- 0..(tile - 1), reduce: canvas do
      canvas -> Raster.put_pixel(canvas, left + x, top + y, Raster.get_pixel(raster, x, y))
    end
  end

  @doc "The index showing at `at_ms` for an art whose first index is `index`; `index` itself when it is not animated."
  @spec index_at(%{anim: map()}, pos_integer(), integer()) :: pos_integer()
  def index_at(%{anim: anim}, index, at_ms) do
    case Map.get(anim, index) do
      nil ->
        index

      %{indices: indices, fps: fps} ->
        Enum.at(indices, rem(div(max(at_ms, 0) * fps, 1000), length(indices)))
    end
  end

  @doc "The sheet's pixel size."
  @spec dimensions(t()) :: {pos_integer(), pos_integer()}
  def dimensions(%{tile: tile, columns: columns, rows: rows}), do: {columns * tile, rows * tile}

  @doc """
  What a client needs to draw from the sheet at `url`: the tile size, the columns, the
  void colour as `#rrggbb`, the arts' indices by name, the frames' positions and the
  animations keyed by their first index as a string.
  """
  @spec index(t(), String.t()) :: map()
  def index(sheet, url) do
    {r, g, b} = sheet.void

    %{
      url: url,
      tile: sheet.tile,
      columns: sheet.columns,
      void: "#" <> Base.encode16(<<r, g, b>>, case: :lower),
      arts: Map.new(sheet.arts, fn {art, index} -> {name(art), index} end),
      frames: sheet.frames,
      anim: Map.new(sheet.anim, fn {first, anim} -> {Integer.to_string(first), anim} end)
    }
  end

  defp name(art) when is_atom(art), do: Atom.to_string(art)
  defp name(art), do: inspect(art)
end
