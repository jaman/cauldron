defmodule Cauldron2D.GameMaker.Room do
  @moduledoc """
  A room (a `ROOM` entry): a level or screen of the game, `size` `{width, height}`
  pixels, stepped `speed` times a second (GameMaker Studio 2 files set the game's
  speed instead and leave this `0`).

    * `colour` is the background colour `{r, g, b, a}`, drawn when `fill` is set
    * `views` are the room's eight `Cauldron2D.GameMaker.Room.View`s, used when
      `views?` is set
    * `instances` are its `Cauldron2D.GameMaker.Room.Instance`s, in the order the file
      lists them; `creation_order` holds their ids in the order they are created, empty
      for files written before GameMaker 2024.13
    * GameMaker Studio 1 rooms draw `backdrops` (`Cauldron2D.GameMaker.Room.Backdrop`)
      and `tiles` (`Cauldron2D.GameMaker.Room.Tile`); GameMaker Studio 2 rooms leave
      those empty and draw `layers` (`Cauldron2D.GameMaker.Room.Layer`) instead
    * `gravity` is `{x, y}` and `pixels_per_metre` the scale, for rooms with physics
    * `creation_code` is the code entry run when the room starts, `nil` for none
  """

  alias Cauldron2D.GameMaker.Bytes
  alias Cauldron2D.GameMaker.General
  alias Cauldron2D.GameMaker.Room.Backdrop
  alias Cauldron2D.GameMaker.Room.Instance
  alias Cauldron2D.GameMaker.Room.Layer
  alias Cauldron2D.GameMaker.Room.Tile
  alias Cauldron2D.GameMaker.Room.View

  @enforce_keys [:name, :size, :instances]
  defstruct [
    :name,
    :caption,
    :size,
    :speed,
    :persistent,
    :colour,
    :fill,
    :creation_code,
    :views?,
    :physics?,
    :gravity,
    :pixels_per_metre,
    creation_order: [],
    views: [],
    instances: [],
    backdrops: [],
    tiles: [],
    layers: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          caption: String.t() | nil,
          size: {non_neg_integer(), non_neg_integer()},
          speed: non_neg_integer(),
          persistent: boolean(),
          colour: {byte(), byte(), byte(), byte()},
          fill: boolean(),
          creation_code: non_neg_integer() | nil,
          views?: boolean(),
          physics?: boolean(),
          gravity: {number(), number()},
          pixels_per_metre: number(),
          creation_order: [non_neg_integer()],
          views: [View.t()],
          instances: [Instance.t()],
          backdrops: [Backdrop.t()],
          tiles: [Tile.t()],
          layers: [Layer.t()]
        }

  @doc """
  The room at `at`. `instance_size` is the byte length of one placed instance in this
  file (see `Cauldron2D.GameMaker.Room.Instance.read/3`); `general` is the file's.
  """
  @spec read(binary(), non_neg_integer(), General.t(), 36 | 40 | 44 | 48) :: t()
  def read(data, at, %General{} = general, instance_size) do
    order = creation_order_size(general)

    <<_name::little-32, _caption::little-32, width::little-32, height::little-32,
      speed::little-32, persistent::little-32, colour::little-32, fill::little-32,
      creation::little-signed-32, flags::little-32, backdrops::little-32, views::little-32,
      instances::little-32, tiles::little-32, order_list::binary-size(order), physics::little-32,
      _top::little-32, _left::little-32, _right::little-32, _bottom::little-32,
      gravity_x::binary-4, gravity_y::binary-4, metres::binary-4>> =
      binary_part(data, at, 88 + order)

    %__MODULE__{
      name: Bytes.string_at(data, at),
      caption: Bytes.string_at(data, at + 4),
      size: {width, height},
      speed: speed,
      persistent: persistent != 0,
      colour: Bytes.colour(colour),
      fill: fill != 0,
      creation_code: if(creation >= 0, do: creation),
      views?: Bitwise.band(flags, 1) != 0,
      physics?: physics != 0,
      gravity: {Bytes.float(gravity_x), Bytes.float(gravity_y)},
      pixels_per_metre: Bytes.float(metres),
      backdrops: each(data, backdrops, &Backdrop.read/2),
      views: each(data, views, &View.read/2),
      instances: each(data, instances, &Instance.read(&1, &2, instance_size)),
      tiles: each(data, tiles, &Tile.read/2),
      creation_order: creation_order(data, order_list),
      layers: layers(data, at + 88 + order, general)
    }
  end

  @doc """
  The byte length of a placed instance in a file, measured from the gaps between
  consecutive instances in its rooms' instance lists at `rooms`; `fallback` when no
  room places two.
  """
  @spec instance_size(binary(), [non_neg_integer()], 36 | 40 | 44 | 48) :: 36 | 40 | 44 | 48
  def instance_size(data, rooms, fallback) do
    rooms
    |> Enum.flat_map(fn room -> Bytes.pointers(data, Bytes.u32(data, room + 48)) end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [first, second] -> second - first end)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_gap, count} -> count end, fn -> {fallback, 0} end)
    |> elem(0)
  end

  defp creation_order_size(general), do: if(General.at_least?(general, 2024, 13), do: 4, else: 0)

  defp creation_order(_data, <<>>), do: []

  defp creation_order(data, <<list::little-32>>),
    do: Bytes.u32s(data, list + 4, Bytes.u32(data, list))

  defp layers(_data, _at, %General{format: :gms1}), do: []

  defp layers(data, at, general),
    do: each(data, Bytes.u32(data, at), &Layer.read(&1, &2, general))

  defp each(data, list, read), do: data |> Bytes.pointers(list) |> Enum.map(&read.(data, &1))
end
