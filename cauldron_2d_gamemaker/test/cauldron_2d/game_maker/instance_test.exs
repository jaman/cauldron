defmodule Cauldron2D.GameMaker.InstanceTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.GameMaker.Instance

  defp instance, do: %Instance{id: 1, object: 0, x: 0, y: 0}

  test "speed and direction become hspeed and vspeed with y growing downwards" do
    up = Instance.put_motion(instance(), %{speed: 3, direction: 90})
    assert {up.hspeed, up.vspeed} == {0, -3}

    left = Instance.put_motion(instance(), %{speed: 2, direction: 180})
    assert {left.hspeed, left.vspeed} == {-2, 0}
  end

  test "hspeed and vspeed become speed and direction, and a stop keeps the direction" do
    moving = Instance.put_motion(instance(), %{hspeed: 3.0, vspeed: 3.0})
    assert_in_delta moving.speed, :math.sqrt(18), 1.0e-9
    assert moving.direction == 315.0

    stopped = Instance.put_motion(moving, %{hspeed: 0.0, vspeed: 0.0})
    assert {stopped.speed, stopped.direction} == {0.0, 315.0}
  end
end
