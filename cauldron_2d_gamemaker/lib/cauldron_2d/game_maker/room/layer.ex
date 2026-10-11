defmodule Cauldron2D.GameMaker.Room.Layer do
  @moduledoc """
  A layer of a GameMaker Studio 2 room. Layers draw in order of `depth`, greater first;
  `offset` `{x, y}` shifts everything on the layer and `speed` `{x, y}` scrolls it by
  that many pixels a step.

  `content` depends on the layer's kind:

    * `{:background, map}` — sprite `sprite` (`-1` for a plain fill of `colour`) drawn
      from `first_frame` at `animation` `{rate, :per_second | :per_frame}`, `tiled`
      `{across, down}`, `stretch`ed to the room, or in front of everything as a
      `foreground`
    * `{:instances, ids}` — the ids of the room's instances drawn on this layer
    * `{:assets, map}` — `tiles`, a list of `Cauldron2D.GameMaker.Room.Tile` cut from
      sprites, and `sprites`, each a map of `sprite`, `position`, `scale`, `colour`,
      `animation`, `frame` and `rotation`
    * `{:tiles, map}` — a grid `size` `{columns, rows}` of cells from tileset
      `tileset`; `cells` is a tuple of rows, each a tuple of cells. A cell is `nil`
      when empty, otherwise `{tile, flags}` where `flags` lists any of `:mirror`,
      `:flip` and `:rotate`
    * `{:unknown, kind}` — a kind this reader does not take apart (effects, paths)
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.Room.Tile

  @enforce_keys [:name, :id, :depth, :content]
  defstruct [:name, :id, :depth, :content, offset: {0.0, 0.0}, speed: {0.0, 0.0}, visible: true]

  @type cell :: {non_neg_integer(), [:mirror | :flip | :rotate]} | nil
  @type t :: %__MODULE__{
          name: String.t(),
          id: non_neg_integer(),
          depth: integer(),
          content: {atom(), term()},
          offset: {number(), number()},
          speed: {number(), number()},
          visible: boolean()
        }

  @tile_index 0x7FFFF
  @flags [mirror: 0x10000000, flip: 0x20000000, rotate: 0x40000000]

  @doc "The layer at `at`."
  @spec read(binary(), non_neg_integer()) :: t()
  def read(data, at) do
    <<_name::little-32, id::little-32, kind::little-32, depth::little-signed-32,
      offset_x::binary-4, offset_y::binary-4, speed_x::binary-4, speed_y::binary-4,
      visible::little-32>> = binary_part(data, at, 36)

    %__MODULE__{
      name: Bytes.string_at(data, at),
      id: id,
      depth: depth,
      offset: {Bytes.float(offset_x), Bytes.float(offset_y)},
      speed: {Bytes.float(speed_x), Bytes.float(speed_y)},
      visible: visible != 0,
      content: content(kind, data, at + 36)
    }
  end

  defp content(1, data, at) do
    <<visible::little-32, foreground::little-32, sprite::little-signed-32, across::little-32,
      down::little-32, stretch::little-32, colour::little-32, first::binary-4, rate::binary-4,
      per::little-32>> = binary_part(data, at, 40)

    {:background,
     %{
       visible: visible != 0,
       foreground: foreground != 0,
       sprite: sprite,
       tiled: {across != 0, down != 0},
       stretch: stretch != 0,
       colour: Bytes.colour(colour),
       first_frame: Bytes.float(first),
       animation: {Bytes.float(rate), per(per)}
     }}
  end

  defp content(2, data, at), do: {:instances, Bytes.u32s(data, at + 4, Bytes.u32(data, at))}

  defp content(3, data, at) do
    [tiles, sprites] = Bytes.u32s(data, at, 2)

    {:assets,
     %{
       tiles: data |> Bytes.pointers(tiles) |> Enum.map(&Tile.read(data, &1)),
       sprites: data |> Bytes.pointers(sprites) |> Enum.map(&placed_sprite(data, &1))
     }}
  end

  defp content(4, data, at) do
    [tileset, columns, rows] = Bytes.u32s(data, at, 3)

    cells =
      data
      |> Bytes.u32s(at + 12, columns * rows)
      |> Enum.map(&cell/1)
      |> Enum.chunk_every(max(columns, 1))
      |> Enum.map(&List.to_tuple/1)
      |> List.to_tuple()

    {:tiles, %{tileset: tileset, size: {columns, rows}, cells: cells}}
  end

  defp content(kind, _data, _at), do: {:unknown, kind}

  defp cell(value) do
    case Bitwise.band(value, @tile_index) do
      0 -> nil
      tile -> {tile, for({flag, bit} <- @flags, Bitwise.band(value, bit) != 0, do: flag)}
    end
  end

  defp placed_sprite(data, at) do
    <<_name::little-32, sprite::little-signed-32, x::little-signed-32, y::little-signed-32,
      scale_x::binary-4, scale_y::binary-4, colour::little-32, rate::binary-4, per::little-32,
      frame::binary-4, rotation::binary-4>> = binary_part(data, at, 44)

    %{
      name: Bytes.string_at(data, at),
      sprite: sprite,
      position: {x, y},
      scale: {Bytes.float(scale_x), Bytes.float(scale_y)},
      colour: Bytes.colour(colour),
      animation: {Bytes.float(rate), per(per)},
      frame: Bytes.float(frame),
      rotation: Bytes.float(rotation)
    }
  end

  defp per(0), do: :per_second
  defp per(_), do: :per_frame
end
