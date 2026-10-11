defmodule Cauldron2D.GameMaker.Room.Tile do
  @moduledoc """
  A tile placed on its own: the rectangle `source` `{x, y, width, height}` of
  background (GameMaker Studio 1) or sprite (GameMaker Studio 2 asset layers) `picture`,
  drawn at `{x, y}` scaled by `scale`, blended with `colour`. GameMaker Studio 1 tiles
  order by `depth`, greater drawn first.
  """

  alias Cauldron2D.GameMaker.Bytes

  @enforce_keys [:picture, :position, :source]
  defstruct [:picture, :position, :source, :depth, :id, scale: {1.0, 1.0}, colour: nil]

  @type t :: %__MODULE__{
          picture: integer(),
          position: {integer(), integer()},
          source: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()},
          depth: integer(),
          id: non_neg_integer(),
          scale: {number(), number()},
          colour: {byte(), byte(), byte(), byte()}
        }

  @doc "The tile at `at`."
  @spec read(binary(), non_neg_integer()) :: t()
  def read(data, at) do
    <<x::little-signed-32, y::little-signed-32, picture::little-signed-32, sx::little-32,
      sy::little-32, width::little-32, height::little-32, depth::little-signed-32, id::little-32,
      scale_x::binary-4, scale_y::binary-4, colour::little-32>> = binary_part(data, at, 48)

    %__MODULE__{
      picture: picture,
      position: {x, y},
      source: {sx, sy, width, height},
      depth: depth,
      id: id,
      scale: {Bytes.float(scale_x), Bytes.float(scale_y)},
      colour: Bytes.colour(colour)
    }
  end
end
