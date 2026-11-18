defmodule Cauldron2D.SteeringTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Steering

  defp agent(x, y, vx \\ 0.0, vy \\ 0.0), do: %{x: x, y: y, vx: vx, vy: vy}

  test "seek heads for the target at speed, flee away, arrive slows inside its radius" do
    assert Steering.seek(agent(0.0, 0.0), {3.0, 4.0}, 10.0) == {6.0, 8.0}
    assert Steering.flee(agent(0.0, 0.0), {3.0, 4.0}, 5.0) == {-3.0, -4.0}
    assert Steering.arrive(agent(0.0, 0.0), {1.0, 0.0}, 10.0, 4.0) == {2.5, 0.0}
    assert Steering.arrive(agent(1.0, 0.0), {1.0, 0.0}, 10.0, 4.0) == {0.0, 0.0}
  end

  test "pursuit leads a moving quarry" do
    {vx, vy} = Steering.pursue(agent(0.0, 0.0), agent(10.0, 0.0, 0.0, 5.0), 10.0)
    assert vy > 0 and vx > 0
  end

  test "steering changes velocity no faster than its force" do
    turned = Steering.steer(agent(0.0, 0.0, 10.0, 0.0), {0.0, 10.0}, 20.0, 0.1)
    assert_in_delta :math.sqrt((turned.vx - 10.0) ** 2 + turned.vy ** 2), 2.0, 1.0e-9
  end

  test "separation pushes away from near neighbours only, harder the nearer" do
    me = agent(0.0, 0.0)
    {near, +0.0} = Steering.separation(me, [{0.5, 0.0}], 2.0, 10.0)
    {far, +0.0} = Steering.separation(me, [{1.5, 0.0}], 2.0, 10.0)
    assert near < far and far < 0
    assert Steering.separation(me, [{3.0, 0.0}], 2.0, 10.0) == {0.0, 0.0}
  end
end
