defmodule Cauldron.World.PendingTest do
  use ExUnit.Case, async: true

  alias Cauldron.World.Pending

  defp held(actions), do: %{held: MapSet.new(actions), aim: nil}

  test "a press released before the step holds for that step, then lets go" do
    pending = Pending.new() |> Pending.put(:alice, held([:jump])) |> Pending.put(:alice, held([]))

    assert Pending.inputs(pending) == [{:alice, held([:jump])}]

    after_step = Pending.stepped(pending)
    assert Pending.inputs(after_step) == [{:alice, held([])}]
    assert Pending.stepped(after_step) == %{}
  end

  test "a step after unchanged input leaves nothing waiting" do
    pending = Pending.put(Pending.new(), :alice, held([:left]))

    assert Pending.inputs(pending) == [{:alice, held([:left])}]
    assert Pending.stepped(pending) == %{}
  end
end
