defmodule Cauldron.OpenWorld.Thing do
  @moduledoc """
  Something standing in a `Cauldron.OpenWorld.Cell`: a tree, a rock, a signpost.

    * `kind` — the game's name for what it is
    * `position` — `{x, y}` on the map
    * `height` — how far above the ground its foot is; `0.0` stands on it
    * `turn` — radians about the upright axis
    * `scale` — its size against the kind's own
    * `radius` — how far from `position` it blocks movers; `0.0` blocks nothing
    * `data` — whatever else the game keeps with it

      %Cauldron.OpenWorld.Thing{kind: :pine, position: {12.5, 40.0}, radius: 0.4}
  """

  @type t :: %__MODULE__{
          kind: term(),
          position: {float(), float()},
          height: float(),
          turn: float(),
          scale: float(),
          radius: float(),
          data: term()
        }

  @enforce_keys [:kind, :position]
  defstruct [:kind, :position, height: 0.0, turn: 0.0, scale: 1.0, radius: 0.0, data: nil]
end
