defmodule Cistern.Brain do
  @moduledoc """
  A computer player for `Cauldron2D.Robot`: it walks under the lowest drop in the air.
  """

  @behaviour Cauldron2D.Robot

  @impl true
  def init(_opts), do: nil

  @impl true
  def decide(%{me: nil}, memory, _clock), do: {nil, memory}

  def decide(%{me: me, drops: drops}, memory, _clock) do
    held =
      case Enum.max_by(drops, & &1.y, fn -> nil end) do
        nil -> MapSet.new()
        %{x: x} when x < me.x + 0.5 -> MapSet.new([:left])
        %{x: x} when x > me.x + 0.5 -> MapSet.new([:right])
        _under -> MapSet.new()
      end

    {%{held: held, aim: nil}, memory}
  end

  @impl true
  def gone?(%{me: me, misses_allowed: allowed}), do: me == nil or me.misses >= allowed
end
