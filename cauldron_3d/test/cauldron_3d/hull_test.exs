defmodule Cauldron3D.HullTest do
  use ExUnit.Case, async: true

  alias Cauldron3D.{Hull, Move}

  test "a point traced into a box stops just short of the face it meets" do
    hull = Hull.box({10.0, -5.0, -5.0}, {20.0, 5.0, 5.0})
    trace = Hull.trace(hull, {0.0, 0.0, 0.0}, {30.0, 0.0, 0.0})

    assert_in_delta trace.fraction, (10.0 - 0.03125) / 30.0, 1.0e-9
    assert trace.normal == {-1.0, 0.0, 0.0}
    refute trace.start_solid
  end

  test "a trace that misses the box goes the whole way" do
    trace =
      Hull.trace(
        Hull.box({10.0, 10.0, -5.0}, {20.0, 20.0, 5.0}),
        {0.0, 0.0, 0.0},
        {30.0, 0.0, 0.0}
      )

    assert trace.fraction == 1.0
    assert trace.end_pos == {30.0, 0.0, 0.0}
  end

  test "moving into a wall at an angle slides along it with the part of the velocity along the wall" do
    wall = Hull.box({100.0, -1000.0, -1000.0}, {200.0, 1000.0, 1000.0})
    trace = fn from, to -> Hull.trace(wall, from, to) end
    result = Move.slide(trace, {90.0, 0.0, 0.0}, {100.0, 100.0, 0.0}, 1.0)

    assert result.blocked == [:wall]
    assert result.velocity == {0.0, 100.0, 0.0}
    {x, y, _} = result.origin
    assert_in_delta x, 100.0 - 0.03125, 1.0e-6
    assert y > 90.0
  end
end
