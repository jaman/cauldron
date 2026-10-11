defmodule Cauldron2D.GameMaker.Region do
  @moduledoc """
  A picture's place on a texture page (a `TPAG` item).

  `source` is the rectangle `{x, y, width, height}` cut from texture page `page`.
  `target` is where that rectangle lands, `{x, y, width, height}`, inside a picture of
  `bounds` `{width, height}`: GameMaker trims see-through margins off a picture before
  packing it, and `target` puts them back. A target narrower or shorter than the source
  means the page holds the picture scaled down.
  """

  alias Cauldron2D.GameMaker.Bytes

  @enforce_keys [:source, :target, :bounds, :page]
  defstruct [:source, :target, :bounds, :page]

  @type rectangle :: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
  @type t :: %__MODULE__{
          source: rectangle(),
          target: rectangle(),
          bounds: {non_neg_integer(), non_neg_integer()},
          page: non_neg_integer()
        }

  @doc "Every region in the `TPAG` chunk at `at`, by its offset in the file."
  @spec read_all(binary(), non_neg_integer()) :: %{non_neg_integer() => t()}
  def read_all(data, at) do
    data
    |> Bytes.pointers(at)
    |> Map.new(fn pointer -> {pointer, read(data, pointer)} end)
  end

  @doc "The region at `at`."
  @spec read(binary(), non_neg_integer()) :: t()
  def read(data, at) do
    <<sx::little-16, sy::little-16, sw::little-16, sh::little-16, tx::little-16, ty::little-16,
      tw::little-16, th::little-16, bw::little-16, bh::little-16, page::little-16>> =
      binary_part(data, at, 22)

    %__MODULE__{
      source: {sx, sy, sw, sh},
      target: {tx, ty, tw, th},
      bounds: {bw, bh},
      page: page
    }
  end
end
