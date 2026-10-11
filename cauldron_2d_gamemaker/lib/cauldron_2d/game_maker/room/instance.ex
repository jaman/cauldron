defmodule Cauldron2D.GameMaker.Room.Instance do
  @moduledoc """
  An instance a room places: object `object` at `{x, y}`, with the id the game's code
  knows it by.

  `scale` is `{x, y}`, negative to mirror; `rotation` is in degrees, counter-clockwise;
  `colour` is `{r, g, b, a}` blended over the sprite; `image` is `{speed, index}` from
  GameMaker Studio 2 files and `{1.0, 0}` from older ones. `creation_code` and
  `pre_create_code` are code entry indices, `nil` for none.
  """

  alias Cauldron2D.GameMaker.Bytes

  @enforce_keys [:object, :position, :id]
  defstruct [
    :object,
    :position,
    :id,
    :creation_code,
    :pre_create_code,
    scale: {1.0, 1.0},
    rotation: 0.0,
    colour: {255, 255, 255, 255},
    image: {1.0, 0}
  ]

  @type t :: %__MODULE__{
          object: integer(),
          position: {integer(), integer()},
          id: non_neg_integer(),
          creation_code: non_neg_integer() | nil,
          pre_create_code: non_neg_integer() | nil,
          scale: {number(), number()},
          rotation: number(),
          colour: {byte(), byte(), byte(), byte()},
          image: {number(), integer()}
        }

  @doc """
  The instance at `at`, `size` bytes long: 36 or 40 in GameMaker Studio 1 files, 44 or
  48 in GameMaker Studio 2 files, the longer of each carrying pre-create code.
  """
  @spec read(binary(), non_neg_integer(), 36 | 40 | 44 | 48) :: t()
  def read(data, at, size) do
    <<x::little-signed-32, y::little-signed-32, object::little-signed-32, id::little-32,
      creation::little-signed-32, scale_x::binary-4, scale_y::binary-4, rest::binary>> =
      binary_part(data, at, size)

    instance = %__MODULE__{
      object: object,
      position: {x, y},
      id: id,
      creation_code: code(creation),
      scale: {Bytes.float(scale_x), Bytes.float(scale_y)}
    }

    rest(instance, rest)
  end

  defp rest(instance, <<speed::binary-4, index::little-signed-32, rest::binary>>)
       when byte_size(rest) in [8, 12],
       do: rest(%{instance | image: {Bytes.float(speed), index}}, rest)

  defp rest(instance, <<colour::little-32, rotation::binary-4>>),
    do: %{instance | colour: Bytes.colour(colour), rotation: Bytes.float(rotation)}

  defp rest(instance, <<colour::little-32, rotation::binary-4, pre::little-signed-32>>),
    do: %{
      instance
      | colour: Bytes.colour(colour),
        rotation: Bytes.float(rotation),
        pre_create_code: code(pre)
    }

  defp code(index) when index >= 0, do: index
  defp code(_index), do: nil
end
