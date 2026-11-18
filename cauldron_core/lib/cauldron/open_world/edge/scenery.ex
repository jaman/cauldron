defmodule Cauldron.OpenWorld.Edge.Scenery do
  @moduledoc """
  The edge of a map whose land goes on past where movers can walk: a mover is stopped
  where simulated cells give way to cells that are only shown, or to none, and slides
  along that line.

  Option `:margin` (default `0.0`) keeps movers that far inside the simulated cells.

      Cauldron.OpenWorld.Map.new(cell_size: 64.0, samples: 64, edges: [{Cauldron.OpenWorld.Edge.Scenery, margin: 1.0}])
  """

  @behaviour Cauldron.OpenWorld.Edge

  alias Cauldron.OpenWorld.Map, as: World

  @impl true
  def stop(options, %World{} = map, {from_x, from_y} = from, {to_x, to_y} = to) do
    margin = Keyword.get(options, :margin, 0.0)

    cond do
      open?(map, to, margin) -> {:clear, to}
      open?(map, {to_x, from_y}, margin) -> {:stopped, {to_x, from_y}}
      open?(map, {from_x, to_y}, margin) -> {:stopped, {from_x, to_y}}
      true -> {:stopped, from}
    end
  end

  defp open?(map, {x, y}, margin) do
    Enum.all?(
      [{x, y}, {x + margin, y}, {x - margin, y}, {x, y + margin}, {x, y - margin}],
      &World.simulated?(map, &1)
    )
  end
end
