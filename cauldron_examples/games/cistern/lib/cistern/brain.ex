defmodule Cistern.Brain do
  @moduledoc """
  A computer keeper for `Cauldron.Robot`: it walks under the lowest drop in the air,
  and under the Squall when none is falling.
  """

  @behaviour Cauldron.Robot

  @dead_zone 0.2

  @impl true
  def init(_opts), do: nil

  @impl true
  def decide(%{me: nil}, memory, _clock), do: {nil, memory}

  def decide(%{me: me}, memory, _clock) do
    target =
      case Enum.max_by(me.drops, & &1.y, fn -> nil end) do
        nil -> me.squall.x
        drop -> drop.x
      end

    held =
      cond do
        target < me.centre - @dead_zone -> MapSet.new([:left])
        target > me.centre + @dead_zone -> MapSet.new([:right])
        true -> MapSet.new()
      end

    {%{held: held, aim: nil}, memory}
  end

  @impl true
  def gone?(%{me: me}), do: me == nil or me.out?
end
