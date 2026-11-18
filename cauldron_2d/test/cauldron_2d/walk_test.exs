defmodule Cauldron2D.WalkTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Walk

  test "a blocked diagonal step slides along the open axis, and stops where none is open" do
    open_below = fn {_x, y} -> y < 5.0 end
    assert {:moved, {x, 4.5}} = Walk.slide({4.0, 4.5}, {1, 1}, 1.0, open_below)
    assert_in_delta x, 4.707, 0.001

    assert Walk.slide({4.0, 4.5}, {0, 1}, 1.0, open_below) == :blocked
  end

  test "through an eye, up walks where it looks and right walks to its right" do
    {fx, fy} = Walk.relative({0, -1}, :math.pi() / 2)
    assert_in_delta fx, 0.0, 1.0e-9
    assert_in_delta fy, 1.0, 1.0e-9

    {rx, ry} = Walk.relative({1, 0}, 0.0)
    assert_in_delta rx, 0.0, 1.0e-9
    assert_in_delta ry, 1.0, 1.0e-9
  end
end
