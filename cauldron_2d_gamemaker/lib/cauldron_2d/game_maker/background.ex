defmodule Cauldron2D.GameMaker.Background do
  @moduledoc """
  A background (a `BGND` entry): a picture GameMaker Studio 1 rooms draw behind or in
  front of everything and cut tiles from, and, from GameMaker Studio 2, a tileset.

  `picture` is the `Cauldron2D.GameMaker.Region` the picture comes from. A tileset also
  has a `tiles` map:

    * `size` — `{width, height}` of one tile
    * `border` — `{x, y}`, the pixels between tiles on the page
    * `columns` — tiles across the picture
    * `count` — how many tiles there are
    * `frames` — pictures per tile; above `1` a tile animates, one frame every
      `frame_time` microseconds, through `ids`, which lists each tile's frames in turn

  Tile `n` sits at column `rem(n, columns)` and row `div(n, columns)`, each cell
  `size` plus `border` twice, the picture starting `border` into the cell.
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Region

  @enforce_keys [:name, :picture]
  defstruct [:name, :picture, :smooth, :tiles]

  @type tiles :: %{
          size: {pos_integer(), pos_integer()},
          border: {non_neg_integer(), non_neg_integer()},
          columns: pos_integer(),
          count: non_neg_integer(),
          frames: pos_integer(),
          frame_time: non_neg_integer(),
          ids: [non_neg_integer()]
        }

  @type t :: %__MODULE__{
          name: String.t(),
          picture: Region.t() | nil,
          smooth: boolean(),
          tiles: tiles() | nil
        }

  @doc "The background at `at`; `format` decides whether it carries a tileset."
  @spec read(binary(), non_neg_integer(), %{non_neg_integer() => Region.t()}, atom()) :: t()
  def read(data, at, regions, format) do
    [_name, _transparent, smooth, _preload, picture] = Bytes.u32s(data, at, 5)

    %__MODULE__{
      name: Bytes.string_at(data, at),
      picture: Map.get(regions, picture),
      smooth: smooth != 0,
      tiles: tiles(data, at + 20, format)
    }
  end

  @doc "Where tile `id` sits in the picture, as `{x, y, width, height}`."
  @spec tile_source(t(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()}
  def tile_source(%__MODULE__{tiles: tiles}, id) do
    %{size: {width, height}, border: {border_x, border_y}, columns: columns} = tiles
    column = rem(id, columns)
    row = div(id, columns)

    {column * (width + 2 * border_x) + border_x, row * (height + 2 * border_y) + border_y, width,
     height}
  end

  defp tiles(_data, _at, :gms1), do: nil

  defp tiles(data, at, _format) do
    [_two, width, height, border_x, border_y, columns, frames, count, _zero] =
      Bytes.u32s(data, at, 9)

    <<frame_time::little-64>> = binary_part(data, at + 36, 8)

    %{
      size: {width, height},
      border: {border_x, border_y},
      columns: columns,
      count: count,
      frames: frames,
      frame_time: frame_time,
      ids: Bytes.u32s(data, at + 44, count * frames)
    }
  end
end
