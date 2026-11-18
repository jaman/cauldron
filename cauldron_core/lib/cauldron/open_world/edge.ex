defmodule Cauldron.OpenWorld.Edge do
  @moduledoc """
  What a mover meets where a `Cauldron.OpenWorld.Map`'s simulation ends.

  A map lists its edges as `{module, options}`; `Cauldron.OpenWorld.Map.travel/3` asks
  each in turn where a move from one point to another ends.

      defmodule MyGame.Fence do
        @behaviour Cauldron.OpenWorld.Edge

        @impl true
        def stop(options, map, from, to), do: {:clear, to}
      end

  Built in: `Cauldron.OpenWorld.Edge.Scenery` stops movers where simulated cells give
  way to cells that are only shown, and `Cauldron.OpenWorld.Edge.Backdrop` stops them at
  the map's panels.
  """

  alias Cauldron.OpenWorld.Map, as: World

  @type point :: {float(), float()}

  @doc """
  Where a move from `from` to `to` ends: `{:clear, to}` when this edge is not in the way,
  `{:stopped, point}` with the point the mover reaches when it is.
  """
  @callback stop(options :: keyword(), World.t(), from :: point(), to :: point()) ::
              {:clear, point()} | {:stopped, point()}
end
