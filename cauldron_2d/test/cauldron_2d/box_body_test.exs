defmodule Cauldron2D.BoxBodyTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.BoxBody

  defp grid do
    fn
      {_x, y} when y >= 10 -> :solid
      {x, 7} when x in 3..6 -> :platform
      {8, _y} -> :solid
      _open -> :open
    end
  end

  defp body(at, velocity) do
    {vx, vy} = velocity
    %{BoxBody.new(at, {0.8, 1.8}) | vx: vx, vy: vy}
  end

  defp fall(body, steps),
    do:
      Enum.reduce(1..steps, body, fn _, b -> BoxBody.move(%{b | vy: b.vy + 1.0}, 0.02, grid()) end)

  test "falling, it lands on the top of solid ground and stays grounded there" do
    landed = BoxBody.move(body({1.5, 9.5}, {0.0, 30.0}), 0.05, grid())
    assert {landed.y, landed.grounded?, landed.vy} == {10.0, true, 0.0}
    assert BoxBody.move(landed, 0.02, grid()).grounded?
  end

  test "a platform is landed on from above and passed through from below" do
    assert %{y: 7.0, grounded?: true} = BoxBody.move(body({4.5, 6.5}, {0.0, 20.0}), 0.05, grid())

    rising = BoxBody.move(body({4.5, 8.5}, {0.0, -40.0}), 0.05, grid())
    assert rising.y == 6.5
    refute rising.grounded?
  end

  test "it stops at a solid wall without passing into it" do
    stopped = BoxBody.move(body({6.5, 9.0}, {60.0, 0.0}), 0.1, grid())
    assert stopped.vx == 0.0
    assert stopped.x + stopped.w / 2 <= 8.0
  end

  test "a body walking off a ledge falls until it lands" do
    assert %{grounded?: true, y: 10.0} = fall(body({7.5, 9.0}, {0.0, 0.0}), 200)
  end
end
