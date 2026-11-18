defmodule Cauldron.OpenWorld.Edge.Backdrop do
  @moduledoc """
  The edge of a map built like a room with the distance painted on its walls: a mover is
  stopped in front of each of the map's panels (`Cauldron.OpenWorld.Panel`) and slides
  along it.

  Option `:margin` (default `0.5`) is how far in front of a panel movers stop.

      Cauldron.OpenWorld.Map.new(
        cell_size: 64.0,
        samples: 64,
        edges: [{Cauldron.OpenWorld.Edge.Backdrop, margin: 1.0}],
        panels: [%Cauldron.OpenWorld.Panel{from: {0.0, 128.0}, to: {128.0, 128.0}, height: 60.0, picture: :hills}]
      )
  """

  @behaviour Cauldron.OpenWorld.Edge

  alias Cauldron.OpenWorld.Map, as: World
  alias Cauldron.OpenWorld.Panel

  @impl true
  def stop(options, %World{panels: panels}, from, to) do
    margin = Keyword.get(options, :margin, 0.5)
    pushed = Enum.reduce(panels, to, &kept_off(&1, from, &2, margin))
    settled = Enum.reduce(panels, pushed, &kept_off(&1, from, &2, margin))
    if settled == to, do: {:clear, to}, else: {:stopped, settled}
  end

  defp kept_off(%Panel{from: {ax, ay}, to: {bx, by}}, {fx, fy}, {tx, ty} = to, margin) do
    length = :math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
    pushed_off({ax, ay}, {bx - ax, by - ay}, length, {fx, fy}, {tx, ty}, to, margin)
  end

  defp pushed_off(_start, _run, length, _from, _target, to, _margin) when length <= 0.0, do: to

  defp pushed_off({ax, ay}, {run_x, run_y}, length, {fx, fy}, {tx, ty}, to, margin) do
    {along_x, along_y} = {run_x / length, run_y / length}
    side = if (fx - ax) * -along_y + (fy - ay) * along_x >= 0.0, do: 1.0, else: -1.0
    {out_x, out_y} = {-along_y * side, along_x * side}
    off = (tx - ax) * out_x + (ty - ay) * out_y
    reach = (tx - ax) * along_x + (ty - ay) * along_y

    if off < margin and reach >= -margin and reach <= length + margin,
      do: {tx + out_x * (margin - off), ty + out_y * (margin - off)},
      else: to
  end
end
