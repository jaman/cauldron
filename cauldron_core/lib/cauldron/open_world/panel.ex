defmodule Cauldron.OpenWorld.Panel do
  @moduledoc """
  A standing wall with a picture on it, where a `Cauldron.OpenWorld.Map`'s simulation
  ends: nothing is simulated behind it, and `Cauldron.OpenWorld.Edge.Backdrop` stops
  movers in front of it.

    * `from`, `to` — the ends of its foot, `{x, y}` on the map; the picture runs from
      `from` on its left to `to` on its right, seen from the side movers are on
    * `base` — the height of its foot
    * `height` — how tall it stands
    * `picture` — the game's name for what is painted on it
    * `span` — the part of the picture it shows, `{left, right}` from 0 to 1, so several
      panels in a row share one picture

      %Cauldron.OpenWorld.Panel{from: {0.0, 512.0}, to: {512.0, 512.0}, height: 120.0, picture: :north_range}
  """

  @type t :: %__MODULE__{
          from: {float(), float()},
          to: {float(), float()},
          base: float(),
          height: float(),
          picture: term(),
          span: {float(), float()}
        }

  @enforce_keys [:from, :to, :height, :picture]
  defstruct [:from, :to, :height, :picture, base: 0.0, span: {0.0, 1.0}]
end
