defmodule Cauldron.PressesTest do
  use ExUnit.Case, async: true

  alias Cauldron.Presses

  @jump MapSet.new([:jump])
  @none MapSet.new()

  test "a held action is pressed at its first step only, and released when let go" do
    presses = Presses.new()
    assert Presses.pressed(presses, @jump) == @jump

    presses = Presses.settle(presses, @jump, 0.02)
    assert Presses.pressed(presses, @jump) == @none
    assert Presses.released(presses, @none) == @jump
  end

  test "a press is buffered for its window after it is made, until it is cleared" do
    presses = Presses.new() |> Presses.settle(@jump, 0.02) |> Presses.settle(@none, 0.05)
    assert Presses.buffered?(presses, @none, :jump, 0.1)

    later = Presses.settle(presses, @none, 0.1)
    refute Presses.buffered?(later, @none, :jump, 0.1)

    cleared = Presses.clear(presses, :jump)
    refute Presses.buffered?(cleared, @none, :jump, 0.1)
  end

  test "a press cleared in the step it is made is not pressed again that step nor buffered after" do
    presses = Presses.clear(Presses.new(), :jump)
    refute Presses.buffered?(presses, @jump, :jump, 0.1)

    presses = Presses.settle(presses, @jump, 0.02)
    refute Presses.buffered?(presses, @jump, :jump, 0.1)
  end
end
