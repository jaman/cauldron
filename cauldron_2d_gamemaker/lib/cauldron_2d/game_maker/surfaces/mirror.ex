defmodule Cauldron2D.GameMaker.Surfaces.Mirror do
  @moduledoc """
  A copy of a world's surfaces held apart from the world, as a client on another machine
  holds them. `Cauldron2D.GameMaker.Surfaces.replay/2` applies the world's operations to
  it, drawing with the same `data` and `pictures` the world draws with, and the
  `Surfaces` functions that read or change surfaces take it in place of a world.

      mirror = Mirror.new(data, &Map.get(pictures, &1))
      mirror = Surfaces.replay(mirror, operations)
      Surfaces.rasters(mirror)
  """

  alias Cauldron2D.GameMaker.Data

  @enforce_keys [:data, :pictures]
  defstruct [:data, :pictures, surfaces: %{rasters: %{}, next: 0, ops: []}]

  @type t :: %__MODULE__{
          data: Data.t(),
          pictures: (term() -> FrenchCurve.Raster.t() | nil) | nil,
          surfaces: %{
            rasters: %{non_neg_integer() => FrenchCurve.Raster.t()},
            next: non_neg_integer(),
            ops: list()
          }
        }

  @doc "An empty mirror drawing with `data` and the picture lookup `pictures`."
  @spec new(Data.t(), (term() -> FrenchCurve.Raster.t() | nil) | nil) :: t()
  def new(%Data{} = data, pictures), do: %__MODULE__{data: data, pictures: pictures}
end
