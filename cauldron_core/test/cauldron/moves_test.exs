defmodule Cauldron.MovesTest do
  use ExUnit.Case, async: true

  alias Cauldron.Moves

  @move %{windup: 0.1, active: 0.1, recover: 0.2}

  test "a move is in its wind-up, then active, then recovering, then done" do
    assert Enum.map([0.05, 0.15, 0.25, 0.45], &Moves.part(@move, &1)) ==
             [:windup, :active, :recover, :done]
  end

  test "its frames keep time with its parts" do
    frames = Enum.map([0.0, 0.06, 0.12, 0.21, 0.31, 0.5], &Moves.frame(@move, &1, {2, 1, 2}))
    assert frames == [0, 1, 2, 3, 4, 4]
  end
end
